import AVFoundation
import Accelerate

/// Provides real-time audio level metering using `AVAudioEngine`'s input
/// node tap.
///
/// **Approach**: Installs a tap on `AVAudioEngine.inputNode` to read raw
/// microphone PCM buffers in real time. Computes RMS power, converts to
/// decibels, normalizes to 0.0–1.0, and publishes to the UI at ~30 fps.
///
/// This runs independently of `AVCaptureSession` — no session
/// reconfiguration or extra outputs required.
///
/// **Sendable invariant**: Mutable state is accessed exclusively under
/// `stateLock`, so the type is safely `@unchecked Sendable`.
final class AudioMeterService: NSObject, @unchecked Sendable {

    // MARK: - Constants

    /// Minimum dB value treated as silence.
    private static let silenceThresholdDb: Float = -60.0

    /// How long (seconds) the peak indicator holds before decaying.
    private static let peakHoldDuration: TimeInterval = 1.5

    /// Minimum interval between UI updates (~30 fps).
    private static let uiUpdateInterval: TimeInterval = 1.0 / 30.0

    /// Normalized level below which audio is considered "absolute silence".
    /// Slightly above zero to ignore floating-point noise.
    private static let silenceFloor: Float = 0.005

    /// Seconds of sustained absolute silence before the watchdog fires.
    /// Set to 5s to avoid false positives from natural speech pauses.
    private static let silenceWatchdogThreshold: TimeInterval = 5.0

    /// Returns whether a given port type should be treated as an external microphone.
    ///
    /// Uses a deny-list approach rather than an allow-list: any port that is NOT a
    /// known built-in or speaker output is considered external. This correctly handles
    /// USB-C audio adapters and accessories that report their type as `"Other"` —
    /// the string the system logs as `"Endpoint Value Converter failed to find a match
    /// for string 'Other'"` — which would silently fall through a pure allow-list.
    private static func isExternalMicPort(_ portType: AVAudioSession.Port) -> Bool {
        // Ports that are definitively NOT external input devices.
        let builtInPorts: Set<AVAudioSession.Port> = [
            .builtInMic,        // iPhone / iPad built-in microphone
            .builtInSpeaker,    // speaker output, not input
            .builtInReceiver,   // earpiece, not input
            .headphones,        // headphone output (no mic on this port)
            .carAudio,          // car speakers, not a mic input
        ]
        return !builtInPorts.contains(portType)
    }

    // MARK: - Callbacks

    /// Lock protecting callback closures, which are set from `@MainActor`
    /// but read from the audio engine's render thread.
    private let callbackLock = NSLock()

    private var _onLevelsUpdated: (@MainActor @Sendable (Float, Float, Float?, Float?) -> Void)?
    /// Publishes `(ch1Level, ch1Peak, ch2Level?, ch2Peak?)` all normalized 0.0–1.0.
    /// Ch2 values are non-nil only when a stereo input (e.g. dual-channel wireless receiver)
    /// is active. Existing callers that only use the first two parameters continue to work.
    var onLevelsUpdated: (@MainActor @Sendable (Float, Float, Float?, Float?) -> Void)? {
        get { callbackLock.withLock { _onLevelsUpdated } }
        set { callbackLock.withLock { _onLevelsUpdated = newValue } }
    }

    private var _onRouteChanged: (@MainActor @Sendable (Bool, String?) -> Void)?
    /// Publishes `(isExternalMic, micName)` when the audio route changes.
    var onRouteChanged: (@MainActor @Sendable (Bool, String?) -> Void)? {
        get { callbackLock.withLock { _onRouteChanged } }
        set { callbackLock.withLock { _onRouteChanged = newValue } }
    }

    private var _onInputsAvailable: (@MainActor @Sendable ([AVAudioSessionPortDescription]) -> Void)?
    /// Publishes the list of available audio inputs when the route changes.
    var onInputsAvailable: (@MainActor @Sendable ([AVAudioSessionPortDescription]) -> Void)? {
        get { callbackLock.withLock { _onInputsAvailable } }
        set { callbackLock.withLock { _onInputsAvailable = newValue } }
    }

    private var _onSilenceWatchdog: (@MainActor @Sendable (Bool) -> Void)?
    /// Fires when sustained silence is detected (`true`) or when audio
    /// recovers after a silence alert (`false`). The ViewModel should
    /// only act on this when an external mic is active.
    var onSilenceWatchdog: (@MainActor @Sendable (Bool) -> Void)? {
        get { callbackLock.withLock { _onSilenceWatchdog } }
        set { callbackLock.withLock { _onSilenceWatchdog = newValue } }
    }

    // MARK: - Private State

    /// Lock protecting metering state.
    private let stateLock = NSLock()

    // MARK: Ch1 peak-hold state
    private var peakLevel: Float = 0.0
    private var peakTimestamp: TimeInterval = 0.0
    private var lastUIUpdate: TimeInterval = 0.0

    // MARK: Ch2 peak-hold state (only used when isStereoInput)
    private var peakLevel2: Float = 0.0
    private var peakTimestamp2: TimeInterval = 0.0

    /// True when the active audio input is a stereo device (channelCount ≥ 2).
    /// Reset to false when the engine stops. Read by the ViewModel to control
    /// whether a second VU meter bar is shown in the UI.
    private(set) var isStereoInput: Bool = false

    /// Timestamp of the last buffer with level above `silenceFloor`.
    private var lastNonZeroBufferTime: TimeInterval = 0.0
    /// Whether the silence alert has already fired (prevents re-firing
    /// on every subsequent silent buffer).
    private var silenceAlertFired: Bool = false

    /// The audio engine used for input metering.
    private var audioEngine: AVAudioEngine?

    /// Whether the audio session category has been configured at least once.
    private var isSessionConfigured = false

    /// Observer token for route-change notifications.
    private var routeObserver: NSObjectProtocol?

    /// Observer token for interruption notifications.
    private var interruptionObserver: NSObjectProtocol?

    /// Work item for debouncing rapid route-change restarts.
    private var restartWorkItem: DispatchWorkItem?

    // MARK: - Init

    override init() {
        super.init()
    }

    deinit {
        stopMetering()
        stopMonitoringRoute()
    }

    // MARK: - dB Conversion

    /// Maps a decibel value from the range `-60 … 0` to `0.0 … 1.0`.
    static func normalizeDecibels(_ db: Float) -> Float {
        let clamped = max(silenceThresholdDb, min(db, 0.0))
        return (clamped - silenceThresholdDb) / (0.0 - silenceThresholdDb)
    }

    // MARK: - Engine Metering

    /// Configures the audio session once. Subsequent calls are no-ops.
    private func ensureSessionConfigured() {
        guard !isSessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
            try session.setActive(true)
            isSessionConfigured = true
        } catch {
            Log.camera.error("AudioMeterService: audio session setup failed – \(error.localizedDescription)")
        }
    }

    /// Starts the audio engine and installs a tap on the input node
    /// (microphone) to compute real-time levels.
    func startMetering() {
        // Tear down any existing engine first.
        tearDownEngine()

        // Configure audio session once.
        ensureSessionConfigured()
        guard isSessionConfigured else { return }

        // Reset silence watchdog so engine restarts (route changes) don't
        // trigger a false positive from the gap between teardown and start.
        stateLock.lock()
        lastNonZeroBufferTime = CACurrentMediaTime()
        silenceAlertFired = false
        stateLock.unlock()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Guard against invalid format (e.g. no mic permission).
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            Log.camera.error("AudioMeterService: invalid input format sr=\(format.sampleRate) ch=\(format.channelCount)")
            return
        }

        // Detect stereo input and store for VU meter / ViewModel use.
        let stereo = format.channelCount >= 2
        isStereoInput = stereo
        if stereo {
            Log.camera.debug("AudioMeterService: stereo input detected — metering both channels")
        }

        // Install tap with nil format so AVAudioEngine uses the hardware's
        // native format directly, bypassing the endpoint format converter.
        // Passing an explicit format causes an 'Endpoint Value Converter' step
        // that silently fails for USB devices reporting portType 'Other'
        // (e.g. DJI Wireless Mic Rx), leaving the tap installed but receiving
        // no data even though engine.start() returns without error.
        // AVCaptureSession has its own hardware path and is unaffected.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            Log.camera.debug("AudioMeterService: engine started, format=\(format)")
        } catch {
            Log.camera.error("AudioMeterService: engine start failed – \(error.localizedDescription)")
            // Remove the tap from the orphaned engine so it doesn't leak,
            // then schedule a recovery attempt once the session settles.
            engine.inputNode.removeTap(onBus: 0)
            restartEngine(delay: 1.5)
        }
    }

    /// Stops the audio engine and removes the input tap.
    func stopMetering() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        tearDownEngine()
        stopMonitoringRoute()
    }

    /// Tears down the engine without cancelling route monitoring.
    private func tearDownEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
            isStereoInput = false
            Log.camera.debug("AudioMeterService: engine stopped")
        }
    }

    /// Restarts the engine with debouncing. Multiple rapid calls (e.g. from
    /// successive route-change notifications) collapse into a single restart.
    /// - Parameter delay: Seconds to wait before performing the restart.
    ///   Use a longer delay (~0.8s) for route changes so the audio route
    ///   has time to fully settle; use a shorter delay (~0.5s) for
    ///   interruption recovery.
    private func restartEngine(delay: TimeInterval = 0.5) {
        // Cancel any pending restart.
        restartWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Log.camera.debug("AudioMeterService: restarting engine (delay=\(delay)s)")
            self.tearDownEngine()

            // A fresh AVAudioEngine automatically connects its inputNode
            // to the current AVAudioSession preferred input — no session
            // cycling needed. We must NOT call setActive(false) here because
            // AVCaptureSession shares the same AVAudioSession; deactivating
            // would kill the capture session's audio connection.
            self.startMetering()

            // Only re-publish route state if the engine actually started.
            // If startMetering() failed, it has already scheduled its own
            // retry via restartEngine(delay: 1.5). Calling evaluateCurrentRoute()
            // while audioEngine is nil would fire onRouteChanged → ViewModel
            // → reconfigureAudioInput() → another route-change notification,
            // creating a cascade of restarts on a dead engine.
            if self.audioEngine != nil {
                self.evaluateCurrentRoute()
            }
        }
        restartWorkItem = work

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Processes a PCM buffer from the input tap — computes RMS, converts
    /// to dB, normalizes, applies peak hold, and publishes.
    ///
    /// When `isStereoInput` is true, channels 0 and 1 are metered independently
    /// so the VU meter can display separate Ch1/Ch2 bars.
    /// RMS is computed via `vDSP_rmsqv` (SIMD-accelerated).
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = vDSP_Length(buffer.frameLength)
        guard frameLength > 0 else { return }

        // SIMD-accelerated RMS — Ch1 (channel 0, always present).
        var rms: Float = 0
        vDSP_rmsqv(channelData[0], 1, &rms, frameLength)
        let db: Float = rms > 0 ? 20.0 * log10f(rms) : Self.silenceThresholdDb
        let normalizedLevel = Self.normalizeDecibels(db)

        // Ch2 (channel 1) — only when stereo input is active.
        var normalizedLevel2: Float? = nil
        if isStereoInput && buffer.format.channelCount >= 2 {
            var rms2: Float = 0
            vDSP_rmsqv(channelData[1], 1, &rms2, frameLength)
            let db2: Float = rms2 > 0 ? 20.0 * log10f(rms2) : Self.silenceThresholdDb
            normalizedLevel2 = Self.normalizeDecibels(db2)
        }

        let now = CACurrentMediaTime()

        stateLock.lock()

        // Ch1 peak hold.
        if normalizedLevel > peakLevel {
            peakLevel = normalizedLevel
            peakTimestamp = now
        } else if now - peakTimestamp > Self.peakHoldDuration {
            peakLevel += (normalizedLevel - peakLevel) * 0.15
        }
        let peak = peakLevel

        // Ch2 peak hold (independent).
        var peak2: Float? = nil
        if let level2 = normalizedLevel2 {
            if level2 > peakLevel2 {
                peakLevel2 = level2
                peakTimestamp2 = now
            } else if now - peakTimestamp2 > Self.peakHoldDuration {
                peakLevel2 += (level2 - peakLevel2) * 0.15
            }
            peak2 = peakLevel2
        }

        // Silence watchdog: track last non-zero buffer (Ch1 drives this).
        var fireSilenceAlert = false
        var fireSilenceRecovery = false

        if normalizedLevel > Self.silenceFloor {
            lastNonZeroBufferTime = now
            if silenceAlertFired {
                silenceAlertFired = false
                fireSilenceRecovery = true
            }
        } else if !silenceAlertFired
                    && lastNonZeroBufferTime > 0
                    && (now - lastNonZeroBufferTime) > Self.silenceWatchdogThreshold {
            silenceAlertFired = true
            fireSilenceAlert = true
        }

        // Throttle UI updates to ~30 fps.
        let shouldUpdate = (now - lastUIUpdate) >= Self.uiUpdateInterval
        if shouldUpdate {
            lastUIUpdate = now
        }

        stateLock.unlock()

        // Publish to main thread — Task { @MainActor } schedules directly
        // on the main actor without the extra DispatchQueue hop.
        if shouldUpdate, let callback = onLevelsUpdated {
            let l2 = normalizedLevel2
            let p2 = peak2
            Task { @MainActor [callback] in callback(normalizedLevel, peak, l2, p2) }
        }

        // Silence watchdog callbacks (outside the lock).
        if fireSilenceAlert, let callback = onSilenceWatchdog {
            Task { @MainActor [callback] in callback(true) }
        } else if fireSilenceRecovery, let callback = onSilenceWatchdog {
            Task { @MainActor [callback] in callback(false) }
        }
    }

    // MARK: - Route Monitoring

    /// Begins observing `AVAudioSession.routeChangeNotification` and
    /// `interruptionNotification`, and immediately publishes the current
    /// route state.
    func startMonitoringRoute() {
        stopMonitoringRoute()

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        // Publish initial state.
        evaluateCurrentRoute()
    }

    /// Handles an audio route change by detecting the new input, explicitly
    /// setting it as preferred, and restarting the engine.
    private func handleRouteChange(_ notification: Notification) {
        let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) ?? .unknown

        Log.camera.debug("AudioMeterService: route changed, reason=\(reason.rawValue)")

        // Only act on reasons that change the input device.
        switch reason {
        case .newDeviceAvailable:
            // A new mic was plugged in — find and select it.
            autoSelectExternalInput()
            evaluateCurrentRoute()
            guard audioEngine != nil else { return }
            // Use a longer delay (1.2s) so USB devices have time to fully
            // register with the iOS audio system before we connect the engine.
            restartEngine(delay: 1.2)

        case .oldDeviceUnavailable:
            // A mic was unplugged — fall back to built-in.
            autoSelectBuiltInInput()
            evaluateCurrentRoute()
            guard audioEngine != nil else { return }
            restartEngine(delay: 0.8)

        case .override, .routeConfigurationChange:
            evaluateCurrentRoute()
            guard audioEngine != nil else { return }
            restartEngine(delay: 0.8)

        default:
            evaluateCurrentRoute()
        }
    }

    /// Scans available inputs for an external mic and sets it as preferred.
    private func autoSelectExternalInput() {
        let session = AVAudioSession.sharedInstance()
        guard let availableInputs = session.availableInputs else { return }

        // Look for external mic types using the deny-list approach.
        for input in availableInputs {
            if Self.isExternalMicPort(input.portType) {
                do {
                    try session.setPreferredInput(input)
                    Log.camera.debug("AudioMeterService: auto-selected external input: \(input.portName)")
                } catch {
                    Log.camera.error("AudioMeterService: setPreferredInput failed – \(error.localizedDescription)")
                }
                return
            }
        }
    }

    /// Sets the built-in microphone as the preferred input.
    private func autoSelectBuiltInInput() {
        let session = AVAudioSession.sharedInstance()
        guard let availableInputs = session.availableInputs else { return }

        for input in availableInputs where input.portType == .builtInMic {
            do {
                try session.setPreferredInput(input)
                Log.camera.debug("AudioMeterService: auto-selected built-in mic: \(input.portName)")
            } catch {
                Log.camera.error("AudioMeterService: setPreferredInput failed – \(error.localizedDescription)")
            }
            return
        }

        // If no built-in found, reset to system default.
        do {
            try session.setPreferredInput(nil)
            Log.camera.debug("AudioMeterService: reset to system default input")
        } catch {
            Log.camera.error("AudioMeterService: setPreferredInput(nil) failed – \(error.localizedDescription)")
        }
    }

    /// Tears down the engine and restarts it with a debounce so the new
    /// `AVAudioEngine.inputNode` picks up the current preferred input.
    ///
    /// Convenience wrapper around `restartEngine(delay:)` using the longer
    /// 0.8s delay appropriate for route-change settling.
    private func restartEngineWithSessionReset() {
        restartEngine(delay: 0.8)
    }

    /// Handles an audio session interruption (phone call, Siri, etc.).
    private func handleInterruption(_ notification: Notification) {
        let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
        let type = AVAudioSession.InterruptionType(rawValue: typeRaw) ?? .began

        if type == .ended {
            Log.camera.debug("AudioMeterService: interruption ended — restarting engine")
            // Re-activate the session after interruption.
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                Log.camera.error("AudioMeterService: reactivation failed – \(error.localizedDescription)")
            }
            restartEngine(delay: 0.5)
        } else {
            Log.camera.debug("AudioMeterService: interruption began — engine will pause")
        }
    }

    /// Stops observing audio route and interruption changes.
    func stopMonitoringRoute() {
        if let observer = routeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeObserver = nil
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    // MARK: - Gain Control

    /// Returns whether hardware input gain adjustment is available on the
    /// current audio route.
    func isGainAvailable(for device: AVCaptureDevice?) -> Bool {
        AVAudioSession.sharedInstance().isInputGainSettable
    }

    /// Sets the hardware input gain via `AVAudioSession`, clamped to
    /// `0.0 … 1.0`.
    func setGain(_ value: Float, on device: AVCaptureDevice?) {
        let session = AVAudioSession.sharedInstance()
        guard session.isInputGainSettable else { return }
        let clamped = max(0.0, min(value, 1.0))
        do {
            try session.setInputGain(clamped)
        } catch {
            Log.camera.error("AudioMeterService: failed to set gain – \(error.localizedDescription)")
        }
    }

    // MARK: - Input Selection

    /// Sets the preferred audio input and restarts the engine to use it.
    /// - Parameter port: The `AVAudioSessionPortDescription` to switch to,
    ///   or `nil` to reset to system default.
    func selectInput(_ port: AVAudioSessionPortDescription?) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredInput(port)
            Log.camera.debug("AudioMeterService: preferred input set to \(port?.portName ?? "system default")")
        } catch {
            Log.camera.error("AudioMeterService: setPreferredInput failed – \(error.localizedDescription)")
        }
        // Restart engine with a full session reset to ensure the new
        // preferred input takes effect.
        restartEngineWithSessionReset()
    }

    /// Returns the currently active input port, if any.
    var activeInput: AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.inputs.first
    }

    // MARK: - Private Helpers

    /// Inspects `AVAudioSession.sharedInstance().currentRoute` and fires
    /// `onRouteChanged` and `onInputsAvailable` in a single main-thread
    /// dispatch so both callbacks see the same snapshot.
    private func evaluateCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let input = route.inputs.first
        let isExternal: Bool
        if let portType = input?.portType {
            isExternal = Self.isExternalMicPort(portType)
        } else {
            isExternal = false
        }
        let portName = input?.portName
        let inputs = session.availableInputs ?? []

        let routeCallback = onRouteChanged
        let inputsCallback = onInputsAvailable

        guard routeCallback != nil || inputsCallback != nil else { return }

        DispatchQueue.main.async {
            Task { @MainActor in
                routeCallback?(isExternal, portName)
                inputsCallback?(inputs)
            }
        }
    }
    
}
