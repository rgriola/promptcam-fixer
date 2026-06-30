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

    /// Cleared on each engine start; set true on the first processBuffer
    /// callback so we can confirm data is actually flowing into the tap.
    private var hasLoggedFirstBuffer = false

    /// Timer that polls AVAudioSession.currentRoute as a safety net.
    /// iOS does not reliably post routeChangeNotification for USB devices
    /// with portType 'Other' (e.g. DJI Wireless Mic Rx), so we poll the
    /// current input UID once per second and trigger the same handling
    /// path when it changes.
    private var routePollTimer: Timer?

    /// UID of the input port last seen by the poller. Used to detect
    /// changes that iOS notifications miss.
    private var lastSeenInputUID: String?

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
        hasLoggedFirstBuffer = false
        stateLock.unlock()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Guard against invalid format (e.g. no mic permission).
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            Log.camera.error("AudioMeterService: invalid input format sr=\(format.sampleRate) ch=\(format.channelCount)")
            return
        }

        // Log full format so we can verify the correct device is connected.
        let session = AVAudioSession.sharedInstance()
        let activeInputName = session.currentRoute.inputs.first?.portName ?? "none"
        let activeInputType = session.currentRoute.inputs.first?.portType.rawValue ?? "unknown"
        let preferredName   = session.preferredInput?.portName ?? "(system default)"
        Log.camera.info("AudioMeterService: startMetering activeInput=\(activeInputName, privacy: .public) portType=\(activeInputType, privacy: .public) preferred=\(preferredName, privacy: .public) format=\(format.channelCount)ch@\(format.sampleRate)Hz")

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

        // Re-register route observer if it was removed (e.g. stopMetering was
        // called by onDisappear and the engine was later restarted without going
        // through setupAudioMeter again). Does not re-evaluate route — restartEngine
        // handles that after confirming the engine is running.
        if routeObserver == nil {
            Log.camera.warning("AudioMeterService: route observer was nil after startMetering — re-registering")
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                DispatchQueue.main.async { self?.handleRouteChange(reasonRaw: reasonRaw) }
            }
        }
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                DispatchQueue.main.async { self?.handleInterruption(typeRaw: typeRaw) }
            }
        }
    }

    /// Stops the audio engine and removes the input tap.
    func stopMetering() {
        Log.camera.info("AudioMeterService: stopMetering called — engine and route observer will be removed")
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

        // Log the very first buffer after each engine start to confirm
        // data is actually flowing into the tap.
        if !hasLoggedFirstBuffer {
            hasLoggedFirstBuffer = true
            Log.camera.info("AudioMeterService: first buffer received — tap is live. format=\(buffer.format.channelCount, privacy: .public)ch frameLength=\(buffer.frameLength, privacy: .public)")
        }

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
        Log.camera.info("AudioMeterService: route observer registered")

        // Seed the polling baseline so the first tick doesn't fire spuriously.
        lastSeenInputUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid

        // Use queue:nil so the notification is delivered on the posting thread
        // immediately, without waiting for OperationQueue.main which can be
        // delayed by RunLoop mode changes during camera preview rendering.
        // We dispatch explicitly to the main queue inside each handler.
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            DispatchQueue.main.async { self?.handleRouteChange(reasonRaw: reasonRaw) }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            DispatchQueue.main.async { self?.handleInterruption(typeRaw: typeRaw) }
        }

        // Publish initial state.
        evaluateCurrentRoute()

        // Start the polling fallback. 1Hz is rare enough to be cheap but
        // fast enough that users perceive the switch as immediate.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollRouteForChange()
        }
        RunLoop.main.add(timer, forMode: .common)
        routePollTimer = timer
    }

    /// Polling fallback for route changes that iOS notifications miss.
    /// Compares the current input port UID to the last seen value and
    /// triggers the same auto-switch logic if it differs.
    private func pollRouteForChange() {
        let currentUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
        guard currentUID != lastSeenInputUID else { return }
        let previousUID = lastSeenInputUID
        lastSeenInputUID = currentUID
        Log.camera.info("AudioMeterService: poller detected route change uid \(previousUID ?? "nil", privacy: .public) → \(currentUID ?? "nil", privacy: .public)")

        // Reuse the notification handler so a single code path drives both
        // notification-driven and polling-driven route changes. Pass the
        // best-guess reason: a new port appeared → newDeviceAvailable, the
        // current port disappeared → oldDeviceUnavailable.
        let reason: AVAudioSession.RouteChangeReason = currentUID != nil ? .newDeviceAvailable : .oldDeviceUnavailable
        handleRouteChange(reasonRaw: reason.rawValue)
    }

    /// Handles an audio route change by detecting the new input, explicitly
    /// setting it as preferred, and restarting the engine.
    private func handleRouteChange(reasonRaw: UInt?) {
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw ?? 0) ?? .unknown

        Log.camera.debug("AudioMeterService: route changed, reason=\(reason.rawValue)")

        // Log all currently available inputs so we can see what the device sees.
        let allInputs = AVAudioSession.sharedInstance().availableInputs ?? []
        let inputSummary = allInputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
        let currentIn = AVAudioSession.sharedInstance().currentRoute.inputs.first
        Log.camera.info("AudioMeterService: route change detail reason=\(reason.rawValue, privacy: .public) currentInput=\(currentIn?.portName ?? "none", privacy: .public) available=[\(inputSummary, privacy: .public)]")

        // Only act on reasons that change the input device.
        switch reason {
        case .newDeviceAvailable:
            // A new mic was plugged in. Use selectInput() — the same path
            // as manual picker selection — so the engine restarts reliably
            // via the exact mechanism that is known to work.
            let externalPort = findExternalInput()
            Log.camera.info("AudioMeterService: newDeviceAvailable — auto-switching to \(externalPort?.portName ?? "(none found)", privacy: .public)")
            if let port = externalPort {
                selectInput(port)
                lastSeenInputUID = port.uid
            } else {
                evaluateCurrentRoute()
            }

        case .oldDeviceUnavailable:
            // A mic was unplugged. Switch back to built-in via selectInput()
            // for the same reliable restart path.
            let builtIn = findBuiltInInput()
            Log.camera.info("AudioMeterService: oldDeviceUnavailable — falling back to \(builtIn?.portName ?? "system default", privacy: .public)")
            selectInput(builtIn)  // nil resets to system default
            lastSeenInputUID = builtIn?.uid

        case .override, .routeConfigurationChange:
            evaluateCurrentRoute()
            guard audioEngine != nil else { return }
            restartEngine(delay: 0.8)

        default:
            evaluateCurrentRoute()
        }
    }

    /// Returns the first available external input port, or nil if none found.
    private func findExternalInput() -> AVAudioSessionPortDescription? {
        let session = AVAudioSession.sharedInstance()
        guard let availableInputs = session.availableInputs else { return nil }
        for input in availableInputs {
            Log.camera.debug("AudioMeterService: candidate '\(input.portName, privacy: .public)' portType=\(input.portType.rawValue, privacy: .public) isExternal=\(Self.isExternalMicPort(input.portType), privacy: .public)")
            if Self.isExternalMicPort(input.portType) { return input }
        }
        Log.camera.warning("AudioMeterService: findExternalInput found no external candidate in \(availableInputs.count, privacy: .public) inputs")
        return nil
    }

    /// Returns the built-in microphone port, or nil to fall back to system default.
    private func findBuiltInInput() -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().availableInputs?.first(where: { $0.portType == .builtInMic })
    }

    /// Handles an audio session interruption (phone call, Siri, etc.).
    private func handleInterruption(typeRaw: UInt?) {
        let type = AVAudioSession.InterruptionType(rawValue: typeRaw ?? 0) ?? .began

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
        routePollTimer?.invalidate()
        routePollTimer = nil
        if let observer = routeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeObserver = nil
            Log.camera.info("AudioMeterService: route observer removed")
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
        // Restart engine so the new preferred input takes effect.
        // 0.8s gives the audio route time to settle before reconnecting.
        restartEngine(delay: 0.8)
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

        Task { @MainActor in
            routeCallback?(isExternal, portName)
            inputsCallback?(inputs)
        }
    }
    
}
