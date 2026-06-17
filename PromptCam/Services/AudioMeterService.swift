import AVFoundation

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

    /// Ports that count as an external microphone.
    private static let externalMicPorts: Set<AVAudioSession.Port> = [
        .headsetMic,
        .usbAudio,
        .bluetoothHFP,
        .bluetoothA2DP,
    ]

    // MARK: - Callbacks

    /// Lock protecting callback closures, which are set from `@MainActor`
    /// but read from the audio engine's render thread.
    private let callbackLock = NSLock()

    private var _onLevelsUpdated: (@MainActor @Sendable (Float, Float) -> Void)?
    /// Publishes `(averageLevel, peakLevel)` both normalized 0.0–1.0.
    var onLevelsUpdated: (@MainActor @Sendable (Float, Float) -> Void)? {
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

    // MARK: - Private State

    /// Lock protecting metering state.
    private let stateLock = NSLock()
    private var peakLevel: Float = 0.0
    private var peakTimestamp: TimeInterval = 0.0
    private var lastUIUpdate: TimeInterval = 0.0

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
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
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

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Guard against invalid format (e.g. no mic permission).
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            Log.camera.error("AudioMeterService: invalid input format sr=\(format.sampleRate) ch=\(format.channelCount)")
            return
        }

        // Install tap — buffer size 1024 gives ~23ms at 44.1kHz.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            Log.camera.debug("AudioMeterService: engine started, format=\(format)")
        } catch {
            Log.camera.error("AudioMeterService: engine start failed – \(error.localizedDescription)")
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
            Log.camera.debug("AudioMeterService: engine stopped")
        }
    }

    /// Restarts the engine with debouncing. Multiple rapid calls (e.g. from
    /// successive route-change notifications) collapse into a single restart.
    private func restartEngine() {
        // Cancel any pending restart.
        restartWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Log.camera.debug("AudioMeterService: restarting engine after route/interruption change")
            self.tearDownEngine()
            self.startMetering()
        }
        restartWorkItem = work

        // 500ms delay lets AVAudioSession fully settle the new route.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Processes a PCM buffer from the input tap — computes RMS, converts
    /// to dB, normalizes, applies peak hold, and publishes.
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Compute RMS across channel 0.
        let samples = channelData[0]
        var sumOfSquares: Float = 0.0
        for i in 0..<frameLength {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrtf(sumOfSquares / Float(frameLength))
        let db: Float = rms > 0 ? 20.0 * log10f(rms) : Self.silenceThresholdDb
        let normalizedLevel = Self.normalizeDecibels(db)

        // Update state.
        let now = CACurrentMediaTime()

        stateLock.lock()

        // Peak hold logic.
        if normalizedLevel > peakLevel {
            peakLevel = normalizedLevel
            peakTimestamp = now
        } else if now - peakTimestamp > Self.peakHoldDuration {
            // Decay peak toward current level.
            peakLevel += (normalizedLevel - peakLevel) * 0.15
        }
        let peak = peakLevel

        // Throttle UI updates to ~30 fps.
        let shouldUpdate = (now - lastUIUpdate) >= Self.uiUpdateInterval
        if shouldUpdate {
            lastUIUpdate = now
        }

        stateLock.unlock()

        // Publish to main thread.
        if shouldUpdate, let callback = onLevelsUpdated {
            DispatchQueue.main.async {
                Task { @MainActor in callback(normalizedLevel, peak) }
            }
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
            restartEngineWithSessionReset()

        case .oldDeviceUnavailable:
            // A mic was unplugged — fall back to built-in.
            autoSelectBuiltInInput()
            evaluateCurrentRoute()
            guard audioEngine != nil else { return }
            restartEngineWithSessionReset()

        case .override, .routeConfigurationChange:
            evaluateCurrentRoute()
            guard audioEngine != nil else { return }
            restartEngineWithSessionReset()

        default:
            evaluateCurrentRoute()
        }
    }

    /// Scans available inputs for an external mic and sets it as preferred.
    private func autoSelectExternalInput() {
        let session = AVAudioSession.sharedInstance()
        guard let availableInputs = session.availableInputs else { return }

        // Look for external mic types.
        for input in availableInputs {
            if Self.externalMicPorts.contains(input.portType) {
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
    /// **Important**: We must NOT call `setActive(false)` here because
    /// `AVCaptureSession` shares the same `AVAudioSession`. Deactivating it
    /// kills the capture session's audio connection, causing recordings from
    /// external mics to have no audio.
    private func restartEngineWithSessionReset() {
        restartWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Log.camera.debug("AudioMeterService: restarting engine for new input")
            self.tearDownEngine()

            // A fresh AVAudioEngine automatically connects its inputNode
            // to the current AVAudioSession preferred input — no session
            // cycling needed.
            self.startMetering()

            // Re-publish available inputs and route state.
            self.evaluateCurrentRoute()
        }
        restartWorkItem = work

        // 800ms delay lets the audio route fully settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
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
            restartEngine()
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
    /// `onRouteChanged` and `onInputsAvailable`.
    private func evaluateCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let input = route.inputs.first
        let isExternal: Bool
        if let portType = input?.portType {
            isExternal = Self.externalMicPorts.contains(portType)
        } else {
            isExternal = false
        }
        let portName = input?.portName

        if let callback = onRouteChanged {
            DispatchQueue.main.async {
                Task { @MainActor in callback(isExternal, portName) }
            }
        }

        // Publish available inputs so the UI can offer a picker.
        let inputs = session.availableInputs ?? []
        if let callback = onInputsAvailable {
            DispatchQueue.main.async {
                Task { @MainActor in callback(inputs) }
            }
        }
    }
    
}
