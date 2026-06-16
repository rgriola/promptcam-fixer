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

    // MARK: - Private State

    /// Lock protecting metering state.
    private let stateLock = NSLock()
    private var peakLevel: Float = 0.0
    private var peakTimestamp: TimeInterval = 0.0
    private var lastUIUpdate: TimeInterval = 0.0

    /// The audio engine used for input metering.
    private var audioEngine: AVAudioEngine?

    /// Observer token for route-change notifications.
    private var routeObserver: NSObjectProtocol?

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

    /// Starts the audio engine and installs a tap on the input node
    /// (microphone) to compute real-time levels.
    func startMetering() {
        // Ensure previous engine is torn down.
        stopMetering()

        // Configure AVAudioSession for recording alongside AVCaptureSession.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            Log.camera.error("AudioMeterService: audio session setup failed – \(error.localizedDescription)")
            return
        }

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
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
            Log.camera.debug("AudioMeterService: engine stopped")
        }
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
    /// immediately publishes the current route state.
    func startMonitoringRoute() {
        stopMonitoringRoute()

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleRouteChange()
        }

        // Publish initial state.
        evaluateCurrentRoute()
    }

    /// Handles an audio route change by restarting the engine (so the input
    /// tap rebinds to the new mic) and publishing the updated route state.
    private func handleRouteChange() {
        evaluateCurrentRoute()

        // The AVAudioEngine input tap is bound to the format of the mic that
        // was active when it started. Switching mics (built-in ↔ external)
        // changes the input format, so we must restart the engine.
        guard audioEngine != nil else { return }
        Log.camera.debug("AudioMeterService: route changed — restarting engine")
        stopMetering()
        // Small delay lets AVAudioSession settle the new route before we
        // re-query the input format.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startMetering()
        }
    }

    /// Stops observing audio route changes.
    func stopMonitoringRoute() {
        if let observer = routeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeObserver = nil
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

    // MARK: - Private Helpers

    /// Inspects `AVAudioSession.sharedInstance().currentRoute` and fires
    /// `onRouteChanged`.
    private func evaluateCurrentRoute() {
        let route = AVAudioSession.sharedInstance().currentRoute
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
    }
}
