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
    ///
    /// `nonisolated(unsafe)`: read from the audio render thread on every buffer
    /// (hot path), written only from the main queue in `startMetering` /
    /// `tearDownEngine`. Bool reads are atomic on Apple architectures; locking
    /// would add ~30 lock acquisitions per second for no observable benefit.
    nonisolated(unsafe) private(set) var isStereoInput: Bool = false

    /// Timestamp of the last buffer with level above `silenceFloor`.
    private var lastNonZeroBufferTime: TimeInterval = 0.0
    /// Whether the silence alert has already fired (prevents re-firing
    /// on every subsequent silent buffer).
    private var silenceAlertFired: Bool = false

    /// The audio engine used for input metering.
    private var audioEngine: AVAudioEngine?

    /// Whether the audio session category has been configured at least once.
    private var isSessionConfigured = false

    /// Observer token for interruption notifications.
    private var interruptionObserver: NSObjectProtocol?

    /// Work item for debouncing rapid route-change restarts.
    private var restartWorkItem: DispatchWorkItem?

    /// True after an `AVAudioSession` interruption ends, until an external
    /// caller confirms the paired `AVCaptureSession` has resumed running
    /// (via `reconnectIfPending()`) or the fallback timer fires.
    ///
    /// **Why**: `CameraService` runs its own independent restart pipeline
    /// driven by `AVCaptureSession.wasInterruptedNotification` /
    /// `.interruptionEndedNotification`. If this service also reactivates
    /// `AVAudioSession` and rebuilds its own `AVAudioEngine` on its own
    /// timer at the same moment `CameraService` calls `session.startRunning()`
    /// on `sessionQueue`, the two uncoordinated reactivations race for the
    /// shared `AVAudioSession` and can leave the capture session's video
    /// pipeline frozen even though `isRunning` reads `true` — the same
    /// symptom as the original dictation-freeze bug, just re-triggered by
    /// this service instead of the system. Deferring the reconnect until
    /// the capture session has confirmed it is running again removes the
    /// race entirely.
    private var pendingReconnectAfterInterruption = false

    /// Safety-net timer for `pendingReconnectAfterInterruption`. If no
    /// external caller invokes `reconnectIfPending()` within this window
    /// (e.g. this service is used without a paired `CameraService`, or the
    /// paired session legitimately stays stopped), reconnect independently
    /// so metering doesn't stay dead forever.
    private var reconnectFallbackWorkItem: DispatchWorkItem?
    
    /// One-shot watchdog that verifies the input tap becomes live after
    /// an engine start. If no buffer is received within the delay window,
    /// a single retry restart is attempted.
    private var firstBufferWatchdogWorkItem: DispatchWorkItem?

    /// Guards the watchdog so it only retries once per engine start.
    private var firstBufferRetryCount: Int = 0

    /// True between `AVAudioSession.interruptionNotification` `.began`
    /// and `.ended`. While set, the restart pipeline and the route poller
    /// take no action.
    ///
    /// **Why**: voice dictation (and similar system-owned audio takeovers)
    /// posts `.began`, then temporarily hijacks the input route. The 1 Hz
    /// poller detects the hijack as a route change, calls `selectInput` +
    /// `restartEngine`, which fights the system for ownership. Every
    /// restart triggers another route flip, causing a runaway restart loop
    /// that thrashes `mediaservicesd` and starves `AVCaptureSession`'s
    /// audio path — which manifests as a frozen camera preview even though
    /// `AVCaptureSession` never posts `.wasInterrupted` itself.
    ///
    /// Suspending the pipeline during `.began` lets the system own the
    /// route uncontested; `.ended` re-seeds the baseline UID and issues a
    /// single clean restart.
    ///
    /// Main-thread only: all writers are inside `handleInterruption`
    /// (main-dispatched) and all readers (`pollRouteForChange`,
    /// `handleRouteChange`, `restartEngine` work item) also execute on
    /// main.
    var isInterrupted = false

    /// Cleared on each engine start; set true on the first processBuffer
    /// callback so we can confirm data is actually flowing into the tap.
    ///
    /// `nonisolated(unsafe)`: same justification as `isStereoInput` — read on
    /// every buffer, written from the main queue once per engine start.
    nonisolated(unsafe) private var hasLoggedFirstBuffer = false

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
        
        // Reset first-buffer watchdog state for this engine start.
        firstBufferRetryCount = 0
        firstBufferWatchdogWorkItem?.cancel()
        firstBufferWatchdogWorkItem = nil

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
            
            // Verify that the tap actually becomes live shortly after start.
            scheduleFirstBufferWatchdog(delay: 1.0)
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
        Log.camera.info("AudioMeterService: stopMetering called — engine and route observer will be removed")
        restartWorkItem?.cancel()
        restartWorkItem = nil
        reconnectFallbackWorkItem?.cancel()
        reconnectFallbackWorkItem = nil
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
            firstBufferWatchdogWorkItem?.cancel()
            firstBufferWatchdogWorkItem = nil
            firstBufferRetryCount = 0
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

        // Signpost ID created now (not inside the work item) so the
        // interval's start-to-scheduling latency is visible too if needed,
        // though the interval itself is begun/ended around the actual
        // teardown+start work below.
        let signpostID = Log.cameraSignposter.makeSignpostID()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Neutralize any restart scheduled just before `.began` fired.
            // The `.ended` handler is responsible for scheduling the clean
            // post-interruption restart; don't fight the system in between.
            guard !self.isInterrupted else {
                Log.camera.debug("AudioMeterService: restart suppressed — session interrupted")
                return
            }
            Log.camera.debug("AudioMeterService: restarting engine (delay=\(delay)s)")

            // Signpost interval around the actual rebuild — this is the
            // main-thread work under suspicion for the camera-preview
            // flash. Compare its duration/timestamp against
            // "CaptureSessionRestart" from CameraService in the same trace.
            let state = Log.cameraSignposter.beginInterval("AudioMeterEngineRestart", id: signpostID)
            self.tearDownEngine()

            // A fresh AVAudioEngine automatically connects its inputNode
            // to the current AVAudioSession preferred input — no session
            // cycling needed. We must NOT call setActive(false) here because
            // AVCaptureSession shares the same AVAudioSession; deactivating
            // would kill the capture session's audio connection.
            self.startMetering()
            Log.cameraSignposter.endInterval("AudioMeterEngineRestart", state)

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
    
    /// Schedules a one-shot check to verify the input tap becomes live after an engine start
    /// or route change. If no buffer has arrived within `delay` seconds, and the session is
    /// not interrupted, a single restart attempt is made with a slightly longer delay.
    private func scheduleFirstBufferWatchdog(delay: TimeInterval) {
        // Cancel any previously scheduled watchdog.
        firstBufferWatchdogWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Do not act while the session is interrupted.
            guard !self.isInterrupted else {
                Log.camera.debug("AudioMeterService: watchdog suppressed — session interrupted")
                return
            }
            // Only act if the engine is present and the tap has not gone live yet.
            guard self.audioEngine != nil, !self.hasLoggedFirstBuffer else { return }

            if self.firstBufferRetryCount == 0 {
                self.firstBufferRetryCount = 1
                Log.camera.warning("AudioMeterService: no buffer received after \(delay)s — retrying engine start")
                // Give the audio route extra time to settle before reconnecting.
                self.restartEngine(delay: 1.2)
            } else {
                Log.camera.error("AudioMeterService: no buffer received after retry — giving up")
            }
        }

        firstBufferWatchdogWorkItem = work
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
            
            // Cancel any pending watchdog once the first buffer arrives.
            firstBufferWatchdogWorkItem?.cancel()
            firstBufferWatchdogWorkItem = nil
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

    /// Begins polling `AVAudioSession.currentRoute` for input changes and
    /// observing interruption notifications. Immediately publishes the
    /// current route state.
    ///
    /// Route changes are detected by polling rather than by
    /// `AVAudioSession.routeChangeNotification` because iOS does not
    /// reliably post that notification for USB devices with portType
    /// 'Other' (e.g. DJI Wireless Mic Rx). Polling at 1 Hz is cheap
    /// (single property read) and uniformly reliable across all device
    /// types.
    func startMonitoringRoute() {
        stopMonitoringRoute()
        Log.camera.info("AudioMeterService: route polling started")

        // Seed the polling baseline so the first tick doesn't fire spuriously.
        lastSeenInputUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid

        // Interruption notifications are unrelated to route changes (phone
        // calls, Siri, etc.) and are reliably posted by iOS, so they still
        // use the notification mechanism.
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

        // Start the polling loop. 1 Hz is rare enough to be cheap but fast
        // enough that users perceive the switch as near-immediate.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollRouteForChange()
        }
        RunLoop.main.add(timer, forMode: .common)
        routePollTimer = timer
    }

    /// Polls `AVAudioSession.currentRoute` and triggers the auto-switch
    /// logic when the active input UID changes.
    private func pollRouteForChange() {
        // While an interruption is active (voice dictation, phone call,
        // Siri, etc.) iOS owns the route and may swap it multiple times
        // as the system UI comes and goes. Acting on these transient
        // swaps starts a restart loop; the `.ended` handler will re-seed
        // and restart cleanly.
        guard !isInterrupted else { return }
        let currentUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
        guard currentUID != lastSeenInputUID else { return }
        let previousUID = lastSeenInputUID
        lastSeenInputUID = currentUID

        // Post-interruption settling can briefly report no active input UID
        // and then immediately resolve to the built-in mic. Treat that
        // first nil -> built-in transition as baseline stabilization, not a
        // real device hot-swap.
        if previousUID == nil,
           let currentIn = AVAudioSession.sharedInstance().currentRoute.inputs.first,
           currentIn.portType == .builtInMic,
           !hasAnyExternalAvailableInput() {
            Log.camera.debug("AudioMeterService: route baseline settled to built-in mic; skipping hot-swap handling")
            return
        }

        Log.camera.info("AudioMeterService: poller detected route change uid \(previousUID ?? "nil", privacy: .public) → \(currentUID ?? "nil", privacy: .public)")

        // Best-guess reason: a new port appeared → newDeviceAvailable,
        // the current port disappeared → oldDeviceUnavailable.
        // Edge case: external A → external B (UID changes, both non-nil)
        // maps to .newDeviceAvailable → findExternalInput → picks first
        // external, which is what we want.
        let reason: AVAudioSession.RouteChangeReason = currentUID != nil ? .newDeviceAvailable : .oldDeviceUnavailable
        handleRouteChange(reasonRaw: reason.rawValue)
    }

    private func hasAnyExternalAvailableInput() -> Bool {
        let inputs = AVAudioSession.sharedInstance().availableInputs ?? []
        return inputs.contains { Self.isExternalMicPort($0.portType) }
    }

    /// Handles an audio route change by detecting the new input, explicitly
    /// setting it as preferred, and restarting the engine.
    /// Called from the polling loop in `pollRouteForChange()`.
    private func handleRouteChange(reasonRaw: UInt?) {
        // Defense-in-depth: `pollRouteForChange` already guards, but any
        // future direct caller must also honor the interruption gate.
        guard !isInterrupted else { return }
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

    /// Handles an audio session interruption (phone call, Siri, voice
    /// dictation, etc.).
    ///
    /// On `.began` we suspend the entire restart/route pipeline: the poller
    /// bails out early and any in-flight restart work item no-ops when it
    /// fires. This is the fix for the "voice dictation freezes the camera"
    /// symptom — without suspension, the poller mistakes iOS's transient
    /// route hijack for a hot-swap and enters a restart loop that starves
    /// `mediaservicesd` and stalls `AVCaptureSession`.
    ///
    /// On `.ended` we clear the flag, re-seed the poller's baseline to the
    /// system's post-interruption route (so it doesn't spuriously fire on
    /// the very next tick), then issue a single clean restart.
    ///
    /// Made `internal` so tests can drive the state machine directly
    /// without depending on real `AVAudioSession` interruption delivery.
    func handleInterruption(typeRaw: UInt?) {
        // Fail-safe default: `.began` (raw 1), NOT the enum's raw-value-0
        // which would be `.ended`. If a stray/malformed notification lacks
        // the type key, suspending the pipeline is safer than clearing it.
        let type = AVAudioSession.InterruptionType(
            rawValue: typeRaw ?? AVAudioSession.InterruptionType.began.rawValue
        ) ?? .began

        if type == .ended {
            isInterrupted = false
            Log.camera.debug("\(Log.ts(), privacy: .public) AudioMeterService: interruption ended — deferring restart to reconnectIfPending()")
            // Re-seed the poller's baseline BEFORE restart so it doesn't
            // interpret the newly-settled route as a hot-swap.
            lastSeenInputUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid

            // Do NOT reactivate the session or restart the engine here.
            // `CameraService` is independently restarting `AVCaptureSession`
            // in response to the paired `AVCaptureSession.interruptionEndedNotification`
            // right now, on its own queue. Reactivating `AVAudioSession` and
            // rebuilding this engine at the same moment races that restart.
            // Instead, mark reconnect as pending and wait for the caller to
            // confirm the capture session is running again via
            // `reconnectIfPending()`. A fallback timer covers callers that
            // never invoke it (no paired capture session, or it legitimately
            // stayed stopped).
            pendingReconnectAfterInterruption = true
            reconnectFallbackWorkItem?.cancel()
            let fallbackDelay: TimeInterval = 2.5
            let fallback = DispatchWorkItem { [weak self] in
                guard let self, self.pendingReconnectAfterInterruption else { return }
                Log.camera.notice("AudioMeterService: no external reconnect after \(fallbackDelay)s — reconnecting independently")
                self.reconnectIfPending()
            }
            reconnectFallbackWorkItem = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: fallback)
        } else {
            isInterrupted = true
            // Cancel any pending route-change restart so it doesn't fire
            // during the interruption window and fight the system for the
            // audio route.
            restartWorkItem?.cancel()
            restartWorkItem = nil
            
            // Also cancel the first-buffer watchdog so it doesn't fire during interruption.
            firstBufferWatchdogWorkItem?.cancel()
            firstBufferWatchdogWorkItem = nil

            // A new interruption supersedes any reconnect pending from a
            // previous cycle.
            reconnectFallbackWorkItem?.cancel()
            reconnectFallbackWorkItem = nil
            pendingReconnectAfterInterruption = false
            
            Log.camera.debug("\(Log.ts(), privacy: .public) AudioMeterService: interruption began — engine will pause, restart pipeline suspended")
        }
    }

    /// Reconnects the metering engine after an interruption, but only if a
    /// reconnect is actually pending (i.e. `.ended` fired since the last
    /// reconnect). Safe to call unconditionally — a no-op when nothing is
    /// pending.
    ///
    /// **Call this after the paired `AVCaptureSession` has confirmed it is
    /// running again** (e.g. from `CameraService.onSessionRunningStateChanged`
    /// firing `true`). Sequencing the reconnect behind that confirmation is
    /// what avoids the dueling-reactivation race described on
    /// `pendingReconnectAfterInterruption`.
    func reconnectIfPending() {
        guard pendingReconnectAfterInterruption else { return }
        pendingReconnectAfterInterruption = false
        reconnectFallbackWorkItem?.cancel()
        reconnectFallbackWorkItem = nil

        // A fresh interruption may have started between `.ended` and this
        // call (e.g. rapid Siri + dictation back-to-back) — don't fight it.
        guard !isInterrupted else {
            Log.camera.debug("AudioMeterService: reconnect skipped — new interruption in progress")
            return
        }

        // Re-activate the session. By this point the paired capture session
        // (if any) has already confirmed it is running, so this no longer
        // races another client's reactivation attempt.
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
