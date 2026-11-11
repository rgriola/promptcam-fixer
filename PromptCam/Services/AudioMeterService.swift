import Accelerate
import AVFoundation

/// Provides real-time audio level metering using `AVAudioEngine`'s input node tap.
///
/// **Approach**: Installs a tap on `AVAudioEngine.inputNode` to read raw microphone PCM buffers in real time.
/// Computes RMS power, converts to decibels, normalizes to 0.0–1.0, and publishes to the UI at ~30 fps.
///
/// This runs independently of `AVCaptureSession` — no session reconfiguration or extra outputs required.
///
/// **Sendable assumptions**: Peak/silence/UI-throttle state uses `stateLock`; callbacks and interruption sequencing
/// use separate locks. Other state relies on the queue / `nonisolated(unsafe)` assumptions below, hence unchecked.
final class AudioMeterService: NSObject, @unchecked Sendable {
    // MARK: - Constants

    /// Minimum dB value treated as silence.
    private static let silenceThresholdDb: Float = -60.0

    /// How long (seconds) the peak indicator holds before decaying.
    private static let peakHoldDuration: TimeInterval = 1.5

    /// Minimum interval between UI updates (~30 fps).
    private static let uiUpdateInterval: TimeInterval = 1.0 / 30.0

    /// Peak amplitude below which the input is treated as truly dead.
    ///
    /// Measured on a DJI Wireless Mic Rx: transmitters off delivers exact digital zero, while a quiet room with
    /// the transmitters on still peaks at −50…−60 dBFS. −80 dBFS sits ~20 dB under real room tone and well above
    /// zero, separating the two without tripping on a receiver that emits dither or a DC offset rather than hard zero.
    private static let silencePeakFloor: Float = 0.0001

    /// Seconds of sustained absolute silence before the watchdog fires: 5s avoids false positives from natural speech pauses.
    private static let silenceWatchdogThreshold: TimeInterval = 5.0

    /// Returns whether a given port type should be treated as an external microphone.
    ///
    /// Uses a deny-list rather than an allow-list: any port that is NOT a known built-in or speaker output is external.
    /// This handles USB-C audio adapters and accessories reporting `"Other"` — logged by the system as
    /// `"Endpoint Value Converter failed to find a match for string 'Other'"` — which a pure allow-list would miss.
    private static func isExternalMicPort(_ portType: AVAudioSession.Port) -> Bool {
        // Ports that are definitively NOT external input devices.
        let builtInPorts: Set<AVAudioSession.Port> = [
            .builtInMic, // iPhone / iPad built-in microphone
            .builtInSpeaker, // speaker output, not input
            .builtInReceiver, // earpiece, not input
            .headphones, // headphone output (no mic on this port)
            .carAudio, // car speakers, not a mic input
        ]
        return !builtInPorts.contains(portType)
    }

    // MARK: - Callbacks

    /// Lock protecting callback closures, set from `@MainActor` but read from the audio engine's render thread.
    private let callbackLock = NSLock()

    private var _onLevelsUpdated: (@MainActor @Sendable (Float, Float, Float?, Float?) -> Void)?
    /// Publishes normalized `(ch1Level, ch1Peak, ch2Level?, ch2Peak?)` (0.0–1.0); Ch2 is non-nil only for stereo input
    /// (e.g. dual-channel wireless receivers). Existing callers using only the first two parameters continue to work.
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
    /// Fires for sustained silence (`true`) or recovery after an alert (`false`); the ViewModel should act only for an external mic.
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

    /// True for stereo inputs (channelCount ≥ 2), reset on engine stop; the ViewModel uses this to show a second VU bar.
    ///
    /// `nonisolated(unsafe)`: read on the audio render thread for every buffer (hot path), written on the main queue
    /// in `startMetering` / `tearDownEngine`. This assumes atomic Bool reads on Apple architectures; locking would add
    /// ~30 acquisitions per second for no observable benefit. Hardware atomicity alone is not Swift synchronization.
    private(set) nonisolated(unsafe) var isStereoInput: Bool = false

    /// Timestamp of the last buffer peaking above `silencePeakFloor`.
    private var lastNonZeroBufferTime: TimeInterval = 0.0
    /// Whether the silence alert has already fired (prevents re-firing on every subsequent silent buffer).
    private var silenceAlertFired: Bool = false

    /// UID of an input the user explicitly picked. While it is available, route polling must not auto-switch away.
    private var userPreferredInputUID: String?

    /// The audio engine used for input metering.
    private var audioEngine: AVAudioEngine?

    /// Whether the audio session category has been configured at least once.
    private var isSessionConfigured = false

    /// Observer token for interruption notifications.
    private var interruptionObserver: NSObjectProtocol?

    /// Task for debouncing rapid route-change restarts.
    private var restartTask: Task<Void, Never>?

    /// True after an `AVAudioSession` interruption ends until an external caller confirms the paired
    /// `AVCaptureSession` resumed running (via `reconnectIfPending()`) or the fallback timer fires.
    ///
    /// **Why**: `CameraService` has a separate restart pipeline driven by `AVCaptureSession.wasInterruptedNotification`
    /// / `.interruptionEndedNotification`. If this service reactivates `AVAudioSession` and rebuilds `AVAudioEngine`
    /// on its own timer while `CameraService` calls `session.startRunning()` on `sessionQueue`, the reactivations race
    /// for the shared `AVAudioSession`. This can freeze the capture video pipeline even when `isRunning` reads `true`:
    /// the original dictation-freeze symptom, re-triggered by this service rather than the system. Waiting until the
    /// capture session confirms it is running removes the race.
    private var pendingReconnectAfterInterruption = false

    /// Safety-net for `pendingReconnectAfterInterruption`: if no caller invokes `reconnectIfPending()` in time
    /// (no paired `CameraService` or its session legitimately stays stopped), reconnect independently so metering recovers.
    private var reconnectFallbackTask: Task<Void, Never>?

    /// One-shot watchdog: if no input-tap buffer arrives within the delay after engine start, attempt one retry restart.
    /// Main-queue engine/watchdog management and the audio render callback access this task without synchronization.
    private var firstBufferWatchdogTask: Task<Void, Never>?

    /// Guards the watchdog so it only retries once per engine start.
    private var firstBufferRetryCount: Int = 0

    /// True from `AVAudioSession.interruptionNotification` `.began` to `.ended`; disables the restart pipeline and poller.
    ///
    /// **Why**: dictation (and other system-owned audio takeovers) posts `.began` and temporarily hijacks the route.
    /// The 1 Hz poller sees a change, calls `selectInput` + `restartEngine`, and fights the system. Each restart flips
    /// the route again, forming a runaway loop that thrashes `mediaservicesd`, starves `AVCaptureSession`'s audio path,
    /// and freezes preview without `AVCaptureSession` itself posting `.wasInterrupted`.
    ///
    /// During `.began`, suspension leaves the route to the system; `.ended` re-seeds the baseline UID and defers a
    /// single clean restart until capture resumes or the fallback fires.
    ///
    /// Main-thread only: all writers (`handleInterruption`, main-dispatched) and readers (`pollRouteForChange`,
    /// `handleRouteChange`, `restartEngine` work item) execute on main.
    var isInterrupted = false

    /// Cleared on each engine start; set true on the first processBuffer callback to confirm data is flowing into the tap.
    ///
    /// `nonisolated(unsafe)`: like `isStereoInput`, this relies on the hardware-atomic / lock-avoidance assumption.
    /// The tap reads/sets it; main resets it once per engine start and the main-queue watchdog also reads it.
    private nonisolated(unsafe) var hasLoggedFirstBuffer = false

    /// Uptime of the last throttled level log, so the 1 Hz diagnostic trace doesn't run on every buffer.
    ///
    /// `nonisolated(unsafe)`: touched only from the audio tap thread.
    private nonisolated(unsafe) var lastLevelLogUptime: CFTimeInterval = 0

    /// Safety-net 1 Hz poll of `AVAudioSession.currentRoute`: iOS may omit routeChangeNotification for USB portType
    /// 'Other' (e.g. DJI Wireless Mic Rx), so input UID changes use the same handling path.
    private var routePollTimer: Timer?

    /// UID of the input port last seen by the poller, used to detect changes that iOS notifications miss.
    private var lastSeenInputUID: String?

    /// Last-poll input UIDs, separate from `lastSeenInputUID`: devices can appear/disappear without changing the route.
    private var lastSeenAvailableUIDs: Set<String> = []

    /// Guards `nextInterruptionSequence`, which is stamped on the notification thread rather than the main queue.
    private let interruptionSequenceLock = NSLock()

    /// Monotonic counter stamped onto each interruption notification at arrival, before the hop to main.
    private var nextInterruptionSequence: UInt64 = 0

    /// Highest sequence already applied to the interruption state machine. Main-queue only.
    private var lastHandledInterruptionSequence: UInt64 = 0

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
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers],
            )
            try session.setActive(true)
            isSessionConfigured = true
        } catch {
            Log.camera.error("AudioMeterService: audio session setup failed – \(error.localizedDescription)")
        }
    }

    /// Starts the audio engine and installs a tap on the input node (microphone) to compute real-time levels.
    func startMetering() {
        // Tear down any existing engine first.
        tearDownEngine()

        // Configure audio session once.
        ensureSessionConfigured()
        guard isSessionConfigured else { return }

        // Reset the silence watchdog so engine restarts (route changes) don't falsely alert during the teardown/start gap.
        stateLock.lock()
        lastNonZeroBufferTime = CACurrentMediaTime()
        let wasSilenceAlertFired = silenceAlertFired
        silenceAlertFired = false
        hasLoggedFirstBuffer = false
        stateLock.unlock()

        // Clearing the flag without telling the UI would strand a latched banner: the service forgets it alerted
        // while the warning stays up. If the new route is also silent the watchdog simply fires again.
        if wasSilenceAlertFired, let callback = onSilenceWatchdog {
            Task { @MainActor [callback] in callback(false) }
        }

        // Reset first-buffer watchdog state for this engine start.
        firstBufferRetryCount = 0
        firstBufferWatchdogTask?.cancel()
        firstBufferWatchdogTask = nil

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Guard against invalid format (e.g. no mic permission).
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.camera.error("AudioMeterService: invalid input format sr=\(format.sampleRate) ch=\(format.channelCount)")
            return
        }

        // Log full format so we can verify the correct device is connected.
        let session = AVAudioSession.sharedInstance()
        let activeInputName = session.currentRoute.inputs.first?.portName ?? "none"
        let activeInputType = session.currentRoute.inputs.first?.portType.rawValue ?? "unknown"
        let preferredName = session.preferredInput?.portName ?? "(system default)"
        Log.camera.info("""
        AudioMeterService: startMetering activeInput=\(activeInputName, privacy: .public) \
        portType=\(activeInputType, privacy: .public) preferred=\(preferredName, privacy: .public) \
        format=\(format.channelCount)ch@\(format.sampleRate)Hz
        """)

        logEngineOwnershipDiagnostics(session: session, format: format)

        // Detect stereo input and store for VU meter / ViewModel use.
        let stereo = format.channelCount >= 2
        isStereoInput = stereo
        if stereo {
            Log.camera.debug("AudioMeterService: stereo input detected — metering both channels")
        }

        // Install the tap with nil format so AVAudioEngine uses the hardware's native format, bypassing the endpoint
        // format converter. An explicit format causes an 'Endpoint Value Converter' step that silently fails for USB
        // devices reporting portType 'Other' (e.g. DJI Wireless Mic Rx): the tap remains installed but receives no data
        // even though engine.start() succeeds. AVCaptureSession has its own hardware path and is unaffected.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            audioEngine = engine
            Log.camera.debug("AudioMeterService: engine started, format=\(format)")

            // Verify that the tap actually becomes live shortly after start.
            scheduleFirstBufferWatchdog(delay: 1.0)
        } catch {
            Log.camera.error("AudioMeterService: engine start failed – \(error.localizedDescription)")
            // Remove the tap from the orphaned engine so it doesn't leak, then schedule recovery once the session settles.
            engine.inputNode.removeTap(onBus: 0)
            restartEngine(delay: 1.5)
        }
    }

    /// Records which mic the metering tap will claim and whether it is a single-input-stream device that can't be
    /// shared with `AVCaptureSession`. If the recording comes back silent, this says whether contention is plausible.
    private func logEngineOwnershipDiagnostics(session: AVAudioSession, format: AVAudioFormat) {
        guard let input = session.currentRoute.inputs.first else {
            Log.audio.error("\(Log.ts(), privacy: .public) [meter] engine starting with NO route input")
            return
        }
        let portType = input.portType
        let exclusiveRisk = portType == .usbAudio || portType.rawValue == "Other"
        Log.audio.notice("""
        \(Log.ts(), privacy: .public) [meter] engine CLAIMING input '\(input.portName, privacy: .public)' \
        uid=\(input.uid, privacy: .public) portType=\(portType.rawValue, privacy: .public) \
        format=\(format.channelCount, privacy: .public)ch@\(format.sampleRate, privacy: .public)Hz \
        exclusiveAccessRisk=\(exclusiveRisk ? "YES" : "no", privacy: .public)
        """)
        if exclusiveRisk {
            Log.audio.notice("""
            \(Log.ts(), privacy: .public) [meter] '\(input.portName, privacy: .public)' may expose a single \
            input stream — if the recording is silent while the meter moves, suspect tap/capture contention
            """)
        }
    }

    /// Stops the audio engine and removes the input tap.
    func stopMetering() {
        Log.audio.notice("\(Log.ts(), privacy: .public) [meter] engine RELEASING input — tap removed")
        Log.camera.info("AudioMeterService: stopMetering called — engine and route observer will be removed")
        restartTask?.cancel()
        restartTask = nil
        reconnectFallbackTask?.cancel()
        reconnectFallbackTask = nil
        pendingReconnectAfterInterruption = false
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

            // Cancel any pending first-buffer watchdog as the engine is torn down.
            firstBufferWatchdogTask?.cancel()
            firstBufferWatchdogTask = nil
            firstBufferRetryCount = 0
        }
    }

    /// Restarts the engine with debouncing: rapid calls (e.g. successive route-change notifications) collapse into one.
    /// - Parameter delay: Seconds to wait before restarting. Use a longer delay (~0.8s) for route changes so the
    ///   audio route can settle; use a shorter delay (~0.5s) for interruption recovery.
    private func restartEngine(delay: TimeInterval = 0.5) {
        // Cancel any pending restart.
        restartTask?.cancel()

        // Create the signpost ID now (not inside the task) so start-to-scheduling latency is visible if needed;
        // the interval itself begins/ends around teardown+start below.
        let signpostID = Log.cameraSignposter.makeSignpostID()

        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Neutralize any restart scheduled just before `.began`: `.ended` schedules the clean post-interruption
            // restart, so don't fight the system in between.
            guard !isInterrupted else {
                Log.camera.debug("AudioMeterService: restart suppressed — session interrupted")
                return
            }
            Log.camera.debug("AudioMeterService: restarting engine (delay=\(delay)s)")

            // Signpost the actual rebuild, the main-thread work under suspicion for the camera-preview flash.
            // Compare its duration/timestamp against "CaptureSessionRestart" from CameraService in the same trace.
            let state = Log.cameraSignposter.beginInterval("AudioMeterEngineRestart", id: signpostID)
            tearDownEngine()

            // A fresh AVAudioEngine connects inputNode to the current AVAudioSession preferred input; no session cycling
            // is needed. Do NOT call setActive(false): AVCaptureSession shares the session, so deactivating it would
            // kill the capture session's audio connection.
            startMetering()
            Log.cameraSignposter.endInterval("AudioMeterEngineRestart", state)

            // Only re-publish route state if the engine started. If startMetering() failed, it already scheduled
            // a retry via restartEngine(delay: 1.5). Calling evaluateCurrentRoute() while audioEngine is nil would fire
            // onRouteChanged → ViewModel → reconfigureAudioInput() → another route-change notification, creating
            // a cascade of restarts on a dead engine.
            if audioEngine != nil {
                evaluateCurrentRoute()
            }
        }
    }

    /// Schedules a one-shot check that the input tap becomes live after an engine start or route change. If no buffer
    /// arrives within `delay` seconds and the session is not interrupted, attempt one restart with a slightly longer delay.
    private func scheduleFirstBufferWatchdog(delay: TimeInterval) {
        // Cancel any previously scheduled watchdog.
        firstBufferWatchdogTask?.cancel()

        firstBufferWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Do not act while the session is interrupted.
            guard !isInterrupted else {
                Log.camera.debug("AudioMeterService: watchdog suppressed — session interrupted")
                return
            }
            // Only act if the engine is present and the tap has not gone live yet.
            guard audioEngine != nil, !hasLoggedFirstBuffer else { return }

            if firstBufferRetryCount == 0 {
                firstBufferRetryCount = 1
                Log.camera.warning("AudioMeterService: no buffer received after \(delay)s — retrying engine start")
                // Give the audio route extra time to settle before reconnecting.
                restartEngine(delay: 1.2)
            } else {
                Log.camera.error("AudioMeterService: no buffer received after retry — giving up")
            }
        }
    }

    /// Processes a PCM buffer from the input tap — computes RMS, converts to dB, normalizes, applies peak hold, and publishes.
    ///
    /// When `isStereoInput` is true, channels 0 and 1 are metered independently for separate Ch1/Ch2 VU bars.
    /// RMS is computed via `vDSP_rmsqv` (SIMD-accelerated).
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = vDSP_Length(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Log the first buffer after each engine start to confirm data is actually flowing into the tap.
        if !hasLoggedFirstBuffer {
            hasLoggedFirstBuffer = true
            Log.camera.info("""
            AudioMeterService: first buffer received — tap is live. \
            format=\(buffer.format.channelCount, privacy: .public)ch frameLength=\(buffer.frameLength, privacy: .public)
            """)

            // Cancel any pending watchdog once the first buffer arrives.
            firstBufferWatchdogTask?.cancel()
            firstBufferWatchdogTask = nil
        }

        // SIMD-accelerated RMS — Ch1 (channel 0, always present).
        var rms: Float = 0
        vDSP_rmsqv(channelData[0], 1, &rms, frameLength)
        let db: Float = rms > 0 ? 20.0 * log10f(rms) : Self.silenceThresholdDb
        let normalizedLevel = Self.normalizeDecibels(db)

        // Peak drives the silence watchdog; a working mic in a quiet room can have RMS below the −60 dBFS display floor.
        var channelPeak: Float = 0
        vDSP_maxmgv(channelData[0], 1, &channelPeak, frameLength)

        // Ch2 (channel 1) — only when stereo input is active.
        var normalizedLevel2: Float? = nil
        var db2: Float?
        if isStereoInput, buffer.format.channelCount >= 2 {
            var rms2: Float = 0
            vDSP_rmsqv(channelData[1], 1, &rms2, frameLength)
            let channel2Db: Float = rms2 > 0 ? 20.0 * log10f(rms2) : Self.silenceThresholdDb
            db2 = channel2Db
            normalizedLevel2 = Self.normalizeDecibels(channel2Db)

            // Max across channels so muting one transmitter of a two-TX receiver doesn't read as silence.
            var channel2Peak: Float = 0
            vDSP_maxmgv(channelData[1], 1, &channel2Peak, frameLength)
            channelPeak = max(channelPeak, channel2Peak)
        }

        // 1 Hz trace aligns the meter with the recorded file's measured peak. Log peak alongside RMS because file
        // analysis reports peak; comparing RMS to peak overstates the gap.
        let logNow = CACurrentMediaTime()
        if logNow - lastLevelLogUptime >= 1.0 {
            lastLevelLogUptime = logNow
            let peakDb = channelPeak > 0 ? 20.0 * log10f(channelPeak) : Self.silenceThresholdDb
            Log.audio.debug("""
            \(Log.ts(), privacy: .public) [meter] rms ch1=\(db, format: .fixed(precision: 1), privacy: .public) \
            ch2=\(db2 ?? -999, format: .fixed(precision: 1), privacy: .public) | \
            peak(max of ch)=\(peakDb, format: .fixed(precision: 1), privacy: .public) dBFS
            """)
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

        // Silence watchdog: driven by peak across all metered channels.
        var fireSilenceAlert = false
        var fireSilenceRecovery = false

        if channelPeak > Self.silencePeakFloor {
            lastNonZeroBufferTime = now
            if silenceAlertFired {
                silenceAlertFired = false
                fireSilenceRecovery = true
            }
        } else if !silenceAlertFired,
                  lastNonZeroBufferTime > 0,
                  (now - lastNonZeroBufferTime) > Self.silenceWatchdogThreshold
        {
            silenceAlertFired = true
            fireSilenceAlert = true
        }

        // Throttle UI updates to ~30 fps.
        let shouldUpdate = (now - lastUIUpdate) >= Self.uiUpdateInterval
        if shouldUpdate {
            lastUIUpdate = now
        }

        stateLock.unlock()

        // Publish to main: Task { @MainActor } schedules directly on the main actor without an extra DispatchQueue hop.
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

    /// Polls `AVAudioSession.currentRoute` for input changes, observes interruptions, and immediately publishes the route.
    ///
    /// Poll rather than use `AVAudioSession.routeChangeNotification`: iOS may omit it for USB portType 'Other'
    /// (e.g. DJI Wireless Mic Rx). A 1 Hz single-property poll is cheap and uniformly reliable across device types.
    func startMonitoringRoute() {
        stopMonitoringRoute()
        Log.camera.info("AudioMeterService: route polling started")

        // Seed the polling baseline so the first tick doesn't fire spuriously.
        lastSeenInputUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
        lastSeenAvailableUIDs = Set((AVAudioSession.sharedInstance().availableInputs ?? []).map(\.uid))

        // Interruptions (phone calls, Siri, etc.) are unrelated to route changes and reliably notified, so observe them.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil,
        ) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard let self else { return }
            let sequence = stampInterruptionSequence()
            // Deliberately `DispatchQueue.main.async`, NOT `Task { @MainActor }`: `.began`/`.ended` form an
            // order-sensitive state machine and GCD guarantees FIFO, whereas unstructured tasks do not.
            DispatchQueue.main.async {
                self.handleInterruption(typeRaw: typeRaw, sequence: sequence)
            }
        }

        // Publish initial state.
        evaluateCurrentRoute()

        // Start the polling loop. 1 Hz is cheap but fast enough that users perceive the switch as near-immediate.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollRouteForChange()
        }
        RunLoop.main.add(timer, forMode: .common)
        routePollTimer = timer
    }

    /// Polls `AVAudioSession.currentRoute` and triggers auto-switch logic when the active input UID changes.
    private func pollRouteForChange() {
        // During an interruption (dictation, phone calls, Siri, etc.), iOS owns the route and may swap it repeatedly
        // as system UI comes/goes. Transient swaps cause a restart loop; `.ended` re-seeds and restarts cleanly.
        guard !isInterrupted else { return }

        let session = AVAudioSession.sharedInstance()
        let available = session.availableInputs ?? []
        let availableUIDs = Set(available.map(\.uid))
        if availableUIDs != lastSeenAvailableUIDs {
            let arrived = availableUIDs.subtracting(lastSeenAvailableUIDs)
            lastSeenAvailableUIDs = availableUIDs

            // An input may appear without iOS moving the route (e.g. AirPods reconnect while a USB mic holds it);
            // the active-input UID then doesn't change, hiding this from the guard below. Republish to refresh the picker.
            Log.camera.info("AudioMeterService: available inputs changed, arrived=[\(arrived.joined(separator: ", "), privacy: .public)]")
            evaluateCurrentRoute()

            // The user's standing pick outranks whatever holds the route, so restore it when the device comes back.
            if let uid = userPreferredInputUID,
               arrived.contains(uid),
               let port = available.first(where: { $0.uid == uid })
            {
                Log.camera.info("AudioMeterService: preferred input '\(port.portName, privacy: .public)' returned — restoring")
                applyPreferredInput(port)
                lastSeenInputUID = port.uid
                return
            }
        }

        let currentUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
        guard currentUID != lastSeenInputUID else { return }
        let previousUID = lastSeenInputUID
        lastSeenInputUID = currentUID

        // Post-interruption settling can briefly report no active input UID, then resolve immediately to the built-in
        // mic. Treat the first nil -> built-in transition as baseline stabilization, not a real device hot-swap.
        if previousUID == nil,
           let currentIn = AVAudioSession.sharedInstance().currentRoute.inputs.first,
           currentIn.portType == .builtInMic,
           !hasAnyExternalAvailableInput()
        {
            Log.camera.debug("AudioMeterService: route baseline settled to built-in mic; skipping hot-swap handling")
            return
        }

        Log.camera.info("""
        AudioMeterService: poller detected route change uid \(previousUID ?? "nil", privacy: .public) \
        → \(currentUID ?? "nil", privacy: .public)
        """)

        // Classify by landed route, not UID nil: USB unplug falls back to built-in and the UID stays non-nil, so
        // classifying by nil would misread unplug as arrival. External A -> B still lands external and is an arrival.
        let landedOnExternal = AVAudioSession.sharedInstance().currentRoute.inputs.first
            .map { Self.isExternalMicPort($0.portType) } ?? false
        let reason: AVAudioSession.RouteChangeReason = landedOnExternal ? .newDeviceAvailable : .oldDeviceUnavailable
        handleRouteChange(reasonRaw: reason.rawValue)
    }

    private func hasAnyExternalAvailableInput() -> Bool {
        let inputs = AVAudioSession.sharedInstance().availableInputs ?? []
        return inputs.contains { Self.isExternalMicPort($0.portType) }
    }

    /// From `pollRouteForChange()`, handles a route change by detecting the new input, setting it preferred, and restarting.
    private func handleRouteChange(reasonRaw: UInt?) {
        // Defense-in-depth: `pollRouteForChange` already guards, but future direct callers must honor the interruption gate.
        guard !isInterrupted else { return }
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw ?? 0) ?? .unknown

        Log.camera.debug("AudioMeterService: route changed, reason=\(reason.rawValue)")

        // Log all currently available inputs so we can see what the device sees.
        let allInputs = AVAudioSession.sharedInstance().availableInputs ?? []
        let inputSummary = allInputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
        let currentIn = AVAudioSession.sharedInstance().currentRoute.inputs.first
        Log.camera.info("""
        AudioMeterService: route change detail reason=\(reason.rawValue, privacy: .public) \
        currentInput=\(currentIn?.portName ?? "none", privacy: .public) \
        available=[\(inputSummary, privacy: .public)]
        """)

        // Only act on reasons that change the input device.
        switch reason {
        case .newDeviceAvailable:
            // An explicit picker choice outranks "first external found" — with two externals, the poller would otherwise
            // yank the route back to whichever enumerates first.
            let target = userPreferredAvailableInput() ?? findExternalInput()
            Log.camera
                .info("AudioMeterService: newDeviceAvailable — auto-switching to \(target?.portName ?? "(none found)", privacy: .public)")
            if let port = target {
                applyPreferredInput(port)
                lastSeenInputUID = port.uid
            } else {
                // The route still moved, so the tap is bound to a stale device.
                evaluateCurrentRoute()
                if audioEngine != nil {
                    restartEngine(delay: 0.8)
                }
            }

        case .oldDeviceUnavailable:
            // Keep `userPreferredInputUID`: the poller restores this standing choice on return. While absent,
            // `userPreferredAvailableInput()` returns nil, so the stale pick cannot block fallback.
            let target = userPreferredAvailableInput() ?? findBuiltInInput()
            Log.camera
                .info("AudioMeterService: oldDeviceUnavailable — falling back to \(target?.portName ?? "system default", privacy: .public)")
            applyPreferredInput(target) // nil resets to system default
            lastSeenInputUID = target?.uid

        case .override, .routeConfigurationChange:
            evaluateCurrentRoute()
            guard audioEngine != nil else { return }
            restartEngine(delay: 0.8)

        case .categoryChange:
            evaluateCurrentRoute()
            // If the tap fails to go live after a category change, schedule a guarded restart.
            if audioEngine != nil {
                scheduleFirstBufferWatchdog(delay: 0.8)
            }

        default:
            evaluateCurrentRoute()
            // For unknown reasons, schedule a guarded watchdog to verify the tap becomes live.
            if audioEngine != nil {
                scheduleFirstBufferWatchdog(delay: 0.8)
            }
        }
    }

    /// Returns the first available external input port, or nil if none found.
    private func findExternalInput() -> AVAudioSessionPortDescription? {
        let session = AVAudioSession.sharedInstance()
        guard let availableInputs = session.availableInputs else { return nil }
        for input in availableInputs {
            Log.camera.debug("""
            AudioMeterService: candidate '\(input.portName, privacy: .public)' \
            portType=\(input.portType.rawValue, privacy: .public) \
            isExternal=\(Self.isExternalMicPort(input.portType), privacy: .public)
            """)
            if Self.isExternalMicPort(input.portType) {
                return input
            }
        }
        Log.camera
            .warning(
                "AudioMeterService: findExternalInput found no external candidate in \(availableInputs.count, privacy: .public) inputs",
            )
        return nil
    }

    /// Returns the built-in microphone port, or nil to fall back to system default.
    private func findBuiltInInput() -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().availableInputs?.first(where: { $0.portType == .builtInMic })
    }

    /// Handles an audio session interruption (phone call, Siri, voice dictation, etc.).
    ///
    /// On `.began` we suspend the restart/route pipeline: the poller bails out and in-flight restart work items no-op
    /// when fired. This fixes "voice dictation freezes the camera": otherwise the poller mistakes iOS's transient route
    /// hijack for a hot-swap and enters a restart loop that starves `mediaservicesd` and stalls `AVCaptureSession`.
    ///
    /// On `.ended`, clear the flag and re-seed the poller's baseline to the post-interruption route (avoiding a spurious
    /// next-tick trigger), then defer one clean restart until capture resumes or the fallback fires.
    ///
    /// Made `internal` so tests can drive the state machine without real `AVAudioSession` interruption delivery.
    func handleInterruption(typeRaw: UInt?) {
        handleInterruption(typeRaw: typeRaw, sequence: nil)
    }

    /// Returns the next monotonic interruption sequence number. Safe to call from the notification delivery thread.
    private func stampInterruptionSequence() -> UInt64 {
        interruptionSequenceLock.withLock {
            nextInterruptionSequence += 1
            return nextInterruptionSequence
        }
    }

    /// - Parameter sequence: Arrival order stamped at notification time, or `nil` for direct callers (tests).
    ///   Out-of-order deliveries are discarded so the state machine stays correct even if transport stops guaranteeing FIFO.
    private func handleInterruption(typeRaw: UInt?, sequence: UInt64?) {
        if let sequence {
            guard sequence > lastHandledInterruptionSequence else {
                Log.camera.error("""
                AudioMeterService: discarding out-of-order interruption seq=\(sequence, privacy: .public) \
                (last=\(self.lastHandledInterruptionSequence, privacy: .public))
                """)
                return
            }
            lastHandledInterruptionSequence = sequence
        }

        // Fail-safe default: `.began` (raw 1), NOT the enum's raw-value-0 (`.ended`). If a stray/malformed notification
        // lacks the type key, suspending the pipeline is safer than clearing it.
        let type = AVAudioSession.InterruptionType(
            rawValue: typeRaw ?? AVAudioSession.InterruptionType.began.rawValue,
        ) ?? .began

        if type == .ended {
            isInterrupted = false
            Log.camera
                .debug("\(Log.ts(), privacy: .public) AudioMeterService: interruption ended — deferring restart to reconnectIfPending()")
            // Re-seed the poller's baseline BEFORE restart so it doesn't interpret the newly-settled route as a hot-swap.
            lastSeenInputUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid

            // Do NOT reactivate the session or restart the engine here: `CameraService` is independently restarting
            // `AVCaptureSession` on its queue after `AVCaptureSession.interruptionEndedNotification`. Reactivating
            // `AVAudioSession` or rebuilding simultaneously races that restart. Wait for `reconnectIfPending()` to
            // confirm capture is running; the fallback covers no confirmation (no paired session or it stayed stopped).
            pendingReconnectAfterInterruption = true
            reconnectFallbackTask?.cancel()
            let fallbackDelay: TimeInterval = 2.5
            reconnectFallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(fallbackDelay * 1_000_000_000))
                guard !Task.isCancelled, let self, pendingReconnectAfterInterruption else { return }
                Log.camera.notice("AudioMeterService: no external reconnect after \(fallbackDelay)s — reconnecting independently")
                reconnectIfPending()
            }
        } else {
            isInterrupted = true
            // Cancel pending route-change restart so it doesn't fire during interruption and fight the system for
            // the audio route.
            restartTask?.cancel()
            restartTask = nil

            // Also cancel the first-buffer watchdog so it doesn't fire during interruption.
            firstBufferWatchdogTask?.cancel()
            firstBufferWatchdogTask = nil

            // A new interruption supersedes any reconnect pending from a previous cycle.
            reconnectFallbackTask?.cancel()
            reconnectFallbackTask = nil
            pendingReconnectAfterInterruption = false

            Log.camera
                .debug(
                    "\(Log.ts(), privacy: .public) AudioMeterService: interruption began — engine will pause, restart pipeline suspended",
                )
        }
    }

    /// Reconnects the metering engine after an interruption only if a reconnect is pending (i.e. `.ended` fired
    /// since the last reconnect). Safe to call unconditionally — a no-op when nothing is pending.
    ///
    /// **Call after the paired `AVCaptureSession` confirms it is running again** (e.g. `CameraService.onSessionRunningStateChanged`
    /// fires `true`). This avoids the dueling-reactivation race described on `pendingReconnectAfterInterruption`.
    func reconnectIfPending() {
        guard pendingReconnectAfterInterruption else { return }
        pendingReconnectAfterInterruption = false
        reconnectFallbackTask?.cancel()
        reconnectFallbackTask = nil

        // A fresh interruption may have started between `.ended` and this call (e.g. rapid Siri + dictation) — don't fight it.
        guard !isInterrupted else {
            Log.camera.debug("AudioMeterService: reconnect skipped — new interruption in progress")
            return
        }

        // Re-activate after the paired capture session (if any) is running, avoiding another client's reactivation race.
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.camera.error("AudioMeterService: reactivation failed – \(error.localizedDescription)")
        }
        Log.camera.debug("\(Log.ts(), privacy: .public) AudioMeterService: reconnecting engine after interruption")
        restartEngine(delay: 0.3)
    }

    /// Stops route polling and interruption observation.
    func stopMonitoringRoute() {
        routePollTimer?.invalidate()
        routePollTimer = nil
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
            Log.camera.info("AudioMeterService: route polling stopped")
        }
    }

    // MARK: - Gain Control

    /// Returns whether hardware input gain adjustment is available on the current audio route.
    func isGainAvailable(for _: AVCaptureDevice?) -> Bool {
        AVAudioSession.sharedInstance().isInputGainSettable
    }

    /// Sets the hardware input gain via `AVAudioSession`, clamped to `0.0 … 1.0`.
    func setGain(_ value: Float, on _: AVCaptureDevice?) {
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

    /// Sets the preferred audio input and restarts the engine. Records the choice so route polling won't auto-switch away.
    /// - Parameter port: The `AVAudioSessionPortDescription` to switch to, or `nil` to reset to system default.
    func selectInput(_ port: AVAudioSessionPortDescription?) {
        userPreferredInputUID = port?.uid
        applyPreferredInput(port)
    }

    /// Applies a preferred input without recording it as a user choice.
    private func applyPreferredInput(_ port: AVAudioSessionPortDescription?) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredInput(port)
            Log.camera.debug("AudioMeterService: preferred input set to \(port?.portName ?? "system default")")
        } catch {
            Log.camera.error("AudioMeterService: setPreferredInput failed – \(error.localizedDescription)")
        }
        // Restart so the new preferred input takes effect; 0.8s lets the audio route settle before reconnecting.
        restartEngine(delay: 0.8)
    }

    /// The input the user explicitly picked, if it is still available.
    private func userPreferredAvailableInput() -> AVAudioSessionPortDescription? {
        guard let uid = userPreferredInputUID else { return nil }
        return AVAudioSession.sharedInstance().availableInputs?.first { $0.uid == uid }
    }

    /// Returns the currently active input port, if any.
    var activeInput: AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.inputs.first
    }

    // MARK: - Private Helpers

    /// Inspects `AVAudioSession.sharedInstance().currentRoute` and fires `onRouteChanged` and `onInputsAvailable`
    /// in a single main-thread dispatch so both callbacks see the same snapshot.
    private func evaluateCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let input = route.inputs.first
        let isExternal: Bool = if let portType = input?.portType {
            Self.isExternalMicPort(portType)
        } else {
            false
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
