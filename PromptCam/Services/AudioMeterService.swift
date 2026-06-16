import AVFoundation

/// Provides real-time audio level metering by polling the audio channels
/// on an `AVCaptureMovieFileOutput`'s audio connection.
///
/// **Approach**: Rather than adding a separate `AVCaptureAudioDataOutput`
/// (which can conflict with an already-running session), this service polls
/// `AVCaptureAudioChannel.averagePowerLevel` and `.peakHoldLevel` via a
/// `DispatchSourceTimer` at ~30 fps. These properties are always available
/// once the session has an audio input and a movie file output.
///
/// **Sendable invariant**: Mutable state is accessed exclusively under
/// `stateLock`, so the type is safely `@unchecked Sendable`.
final class AudioMeterService: NSObject, @unchecked Sendable {

    // MARK: - Constants

    /// Minimum dB value treated as silence.
    private static let silenceThresholdDb: Float = -60.0

    /// How long (seconds) the peak indicator holds before decaying.
    private static let peakHoldDuration: TimeInterval = 1.5

    /// Ports that count as an external microphone.
    private static let externalMicPorts: Set<AVAudioSession.Port> = [
        .headsetMic,
        .usbAudio,
        .bluetoothHFP,
        .bluetoothA2DP,
    ]

    // MARK: - Callbacks

    /// Lock protecting callback closures, which are set from `@MainActor`
    /// but read from the polling timer.
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

    /// The movie file output whose audio connection we poll.
    private weak var movieOutput: AVCaptureMovieFileOutput?

    /// Polling timer for audio levels.
    private var pollingTimer: DispatchSourceTimer?

    /// Observer token for route-change notifications.
    private var routeObserver: NSObjectProtocol?

    // MARK: - Init

    override init() {
        super.init()
    }

    deinit {
        stopPolling()
        stopMonitoringRoute()
    }

    // MARK: - dB Conversion

    /// Maps a decibel value from the range `-60 … 0` to `0.0 … 1.0`.
    static func normalizeDecibels(_ db: Float) -> Float {
        let clamped = max(silenceThresholdDb, min(db, 0.0))
        return (clamped - silenceThresholdDb) / (0.0 - silenceThresholdDb)
    }

    // MARK: - Polling

    /// Begins polling audio levels from the movie file output's audio connection.
    /// - Parameter output: The `AVCaptureMovieFileOutput` already attached to the session.
    func startPolling(movieFileOutput: AVCaptureMovieFileOutput) {
        self.movieOutput = movieFileOutput

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0) // ~30 fps
        timer.setEventHandler { [weak self] in
            self?.pollLevels()
        }
        timer.resume()
        pollingTimer = timer
        Log.camera.debug("AudioMeterService: polling started")
    }

    /// Stops polling audio levels.
    func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func pollLevels() {
        guard let output = movieOutput,
              let connection = output.connection(with: .audio) else { return }

        // Read power levels from the first audio channel.
        let channels = connection.audioChannels
        guard let channel = channels.first else { return }

        let avgDb = channel.averagePowerLevel
        let peakDb = channel.peakHoldLevel

        let normalizedLevel = Self.normalizeDecibels(avgDb)
        let normalizedPeak = Self.normalizeDecibels(peakDb)

        // Apply peak-hold decay logic.
        let now = CACurrentMediaTime()

        stateLock.lock()
        if normalizedPeak > peakLevel {
            peakLevel = normalizedPeak
            peakTimestamp = now
        } else if now - peakTimestamp > Self.peakHoldDuration {
            peakLevel += (normalizedLevel - peakLevel) * 0.15
        }
        let peak = peakLevel
        stateLock.unlock()

        // Publish to main thread.
        if let callback = onLevelsUpdated {
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
