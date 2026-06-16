import AVFoundation
import AudioToolbox

/// Provides real-time audio level metering by tapping into an
/// `AVCaptureSession`'s audio pipeline.
///
/// **Threading model**: The `AVCaptureAudioDataOutputSampleBufferDelegate`
/// callback fires on a private serial queue (`audioQueue`). All mutable
/// metering state is protected by `stateLock` (an `NSLock`). Results are
/// relayed to the main thread via callback closures at ~30 fps.
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

    // MARK: - Public Output

    /// The audio data output to add to the capture session.
    let audioDataOutput = AVCaptureAudioDataOutput()

    // MARK: - Callbacks

    /// Lock protecting callback closures, which are set from `@MainActor`
    /// but read from `audioQueue`.
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

    /// Serial queue for audio sample processing.
    private let audioQueue = DispatchQueue(
        label: "com.promptcam.fixer.audiometer",
        qos: .userInitiated
    )

    /// Lock protecting metering state touched from `audioQueue`.
    private let stateLock = NSLock()
    private var currentLevel: Float = 0.0
    private var peakLevel: Float = 0.0
    private var peakTimestamp: TimeInterval = 0.0
    private var lastUIUpdate: TimeInterval = 0.0

    /// Observer token for route-change notifications.
    private var routeObserver: NSObjectProtocol?

    // MARK: - Init

    override init() {
        super.init()
    }

    deinit {
        stopMonitoringRoute()
    }

    // MARK: - dB Conversion

    /// Maps a decibel value from the range `-60 … 0` to `0.0 … 1.0`.
    static func normalizeDecibels(_ db: Float) -> Float {
        let clamped = max(silenceThresholdDb, min(db, 0.0))
        return (clamped - silenceThresholdDb) / (0.0 - silenceThresholdDb)
    }

    // MARK: - Session Attachment

    /// Adds `audioDataOutput` to the session and sets this service as the
    /// sample-buffer delegate.
    func attach(to session: AVCaptureSession) {
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
            audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)
            Log.camera.debug("AudioMeterService: attached to session")
        } else {
            Log.camera.error("AudioMeterService: cannot add audio data output")
        }
    }

    /// Removes `audioDataOutput` from the session.
    func detach(from session: AVCaptureSession) {
        session.removeOutput(audioDataOutput)
        Log.camera.debug("AudioMeterService: detached from session")
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
            self?.evaluateCurrentRoute()
        }

        // Publish initial state.
        evaluateCurrentRoute()
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
    ///
    /// - Parameter device: Unused but kept for API symmetry with camera
    ///   device references. Gain is controlled via `AVAudioSession`.
    func isGainAvailable(for device: AVCaptureDevice?) -> Bool {
        AVAudioSession.sharedInstance().isInputGainSettable
    }

    /// Sets the hardware input gain via `AVAudioSession`, clamped to
    /// `0.0 … 1.0`.
    ///
    /// - Parameters:
    ///   - value: Desired gain in the range `0.0 … 1.0`.
    ///   - device: Unused but kept for API symmetry. Gain is controlled
    ///     via `AVAudioSession`.
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

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension AudioMeterService: AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // --- Extract audio samples ---
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return }

        guard let data = audioBufferList.mBuffers.mData else { return }
        let sampleCount = Int(audioBufferList.mBuffers.mDataByteSize) / MemoryLayout<Float32>.size
        guard sampleCount > 0 else { return }

        let samples = data.assumingMemoryBound(to: Float32.self)

        // --- Compute RMS ---
        var sumOfSquares: Float = 0.0
        for i in 0..<sampleCount {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrtf(sumOfSquares / Float(sampleCount))
        let db: Float = rms > 0 ? 20.0 * log10f(rms) : Self.silenceThresholdDb
        let normalizedLevel = Self.normalizeDecibels(db)

        // --- Update state ---
        let now = CACurrentMediaTime()

        stateLock.lock()

        currentLevel = normalizedLevel

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

        // --- Publish to main thread ---
        if shouldUpdate, let callback = onLevelsUpdated {
            DispatchQueue.main.async {
                Task { @MainActor in callback(normalizedLevel, peak) }
            }
        }
    }
}
