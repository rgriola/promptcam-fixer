// May 30, 2026 - 4:23pm - GitHub Copilot
// June 8, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add setExposure(to:) for reliable absolute reset
@preconcurrency import AVFoundation
import Photos

enum FocusExposureLockOutcome: Equatable, Sendable {
    case afAeLocked
    case aeLocked
    case afLocked
    case unsupported
}

// MARK: - Device Capabilities

/// Describes video format capabilities for the current device.
struct DeviceCapabilities: Equatable, Sendable {
    /// Whether the device supports cinematic mode (depth capture).
    let supportsCinematicMode: Bool

    /// All valid (resolution, frameRate) pairs for standard mode,
    /// confirmed by interrogating `AVCaptureDevice.formats` directly.
    /// This is the single source of truth — no cross-product inference.
    let standardFormats: [RecordingFormat]

    /// All valid (resolution, frameRate) pairs for cinematic mode,
    /// confirmed by interrogating `AVCaptureDevice.formats` directly.
    let cinematicFormats: [RecordingFormat]

    // MARK: - Derived helpers

    /// All unique resolutions available for a given mode (order: HD before 4K).
    func resolutions(for mode: VideoMode) -> [VideoResolution] {
        let pairs = mode == .cinematic ? cinematicFormats : standardFormats
        var seen = Set<VideoResolution>()
        var result: [VideoResolution] = []
        for pair in pairs where seen.insert(pair.resolution).inserted {
            result.append(pair.resolution)
        }
        return result
    }

    /// All unique frame rates available for a given mode, regardless of resolution.
    func frameRates(for mode: VideoMode) -> [VideoFrameRate] {
        let pairs = mode == .cinematic ? cinematicFormats : standardFormats
        var seen = Set<VideoFrameRate>()
        var result: [VideoFrameRate] = []
        for pair in pairs where seen.insert(pair.frameRate).inserted {
            result.append(pair.frameRate)
        }
        return result
    }

    /// Frame rates valid for a **specific** resolution in a given mode.
    /// Used by the Format Picker to disable fps values that don't work at the selected resolution.
    func frameRates(for mode: VideoMode, resolution: VideoResolution) -> [VideoFrameRate] {
        let pairs = mode == .cinematic ? cinematicFormats : standardFormats
        var seen = Set<VideoFrameRate>()
        var result: [VideoFrameRate] = []
        for pair in pairs
        where pair.resolution == resolution && seen.insert(pair.frameRate).inserted {
            result.append(pair.frameRate)
        }
        return result
    }

    /// Returns whether a specific format combination is confirmed by hardware.
    func isSupported(_ format: RecordingFormat) -> Bool {
        let pairs = format.mode == .cinematic ? cinematicFormats : standardFormats
        return pairs.contains {
            $0.resolution == format.resolution && $0.frameRate == format.frameRate
        }
    }

    /// Adjusts a format to the nearest valid combination for this device.
    func adjusted(_ format: RecordingFormat) -> RecordingFormat {
        var adjusted = format

        // Fall back to standard if cinematic is not supported.
        if format.mode == .cinematic && !supportsCinematicMode {
            adjusted.mode = .standard
        }

        let validResolutions = resolutions(for: adjusted.mode)
        // Clamp resolution to a supported value.
        if !validResolutions.contains(adjusted.resolution) {
            adjusted.resolution = validResolutions.first ?? .hd1080p
        }

        // Clamp frame rate to one valid for the (possibly adjusted) resolution.
        let validFrameRates = frameRates(for: adjusted.mode, resolution: adjusted.resolution)
        if !validFrameRates.contains(adjusted.frameRate) {
            adjusted.frameRate = validFrameRates.first ?? .fps30
        }

        return adjusted
    }
}

/// Manages the AVCaptureSession lifecycle, recording, and focus/exposure hardware.
///
/// **Threading model**: All camera configuration runs on `sessionQueue` (a serial
/// dispatch queue) to avoid blocking the main thread. Results are relayed back to
/// the main thread via callback closures (`onRecordingStateChanged`, `onError`, etc.)
/// using `DispatchQueue.main.async`.
///
/// **Why NSObject**: Required for `AVCaptureFileOutputRecordingDelegate` conformance,
/// which provides `fileOutput(_:didStartRecordingTo:from:)` and
/// `fileOutput(_:didFinishRecordingTo:from:error:)` callbacks.
///
/// **Callback pattern**: The ViewModel binds closures in `bindCallbacks()` at init.
/// This avoids Combine/async bridging complexity while keeping the service testable.
///
/// **Sendable invariant**: All mutable state is mutated exclusively from `sessionQueue`
/// (a serial dispatch queue), so the type is safely `@unchecked Sendable`. Do not add
/// mutable state that is touched from any other queue without updating this guarantee.
final class CameraService: NSObject, CameraServiceProtocol, @unchecked Sendable {
    /// Internal capture session — use `previewSession` from outside this class.
    let session = AVCaptureSession()

    /// Read-only accessor for the preview layer. Do not call session
    /// mutation methods (startRunning, beginConfiguration, etc.) directly.
    var previewSession: AVCaptureSession { session }

    let sessionQueue = DispatchQueue(label: "com.rgriola.promptcam.session")
    let movieFileOutput = AVCaptureMovieFileOutput()
    var currentOutputURL: URL?
    var videoDevice: AVCaptureDevice?
    /// Retained so we can toggle cinematicVideoCaptureEnabled and set simulatedAperture.
    var videoInput: AVCaptureDeviceInput?
    /// The audio capture device — retained for gain control.
    var audioDevice: AVCaptureDevice?
    /// The audio capture input — retained so we can hot-swap on route changes.
    var audioInput: AVCaptureDeviceInput?
    var isSessionConfigured = false

    /// Lock protecting callback closures, which are set from @MainActor
    /// (via bindCallbacks) but read from sessionQueue.
    let callbackLock = NSLock()

    private var _onRecordingStateChanged: (@MainActor @Sendable (Bool) -> Void)?
    var onRecordingStateChanged: (@MainActor @Sendable (Bool) -> Void)? {
        get { callbackLock.withLock { _onRecordingStateChanged } }
        set { callbackLock.withLock { _onRecordingStateChanged = newValue } }
    }

    private var _onSessionRunningStateChanged: (@MainActor @Sendable (Bool) -> Void)?
    var onSessionRunningStateChanged: (@MainActor @Sendable (Bool) -> Void)? {
        get { callbackLock.withLock { _onSessionRunningStateChanged } }
        set { callbackLock.withLock { _onSessionRunningStateChanged = newValue } }
    }

    private var _onFormatApplied: (@MainActor @Sendable (RecordingFormat) -> Void)?
    var onFormatApplied: (@MainActor @Sendable (RecordingFormat) -> Void)? {
        get { callbackLock.withLock { _onFormatApplied } }
        set { callbackLock.withLock { _onFormatApplied = newValue } }
    }

    private var _onDeviceCapabilitiesQueried: (@MainActor @Sendable (DeviceCapabilities) -> Void)?
    var onDeviceCapabilitiesQueried: (@MainActor @Sendable (DeviceCapabilities) -> Void)? {
        get { callbackLock.withLock { _onDeviceCapabilitiesQueried } }
        set { callbackLock.withLock { _onDeviceCapabilitiesQueried = newValue } }
    }

    /// Fired when cinematic mode is enabled with the device's (min, max, default) simulated aperture.
    /// Fired with (0, 0, 0) when cinematic is disabled — signals UI to hide the aperture control.
    private var _onCinematicApertureAvailable: (@MainActor @Sendable (Float, Float, Float) -> Void)?
    var onCinematicApertureAvailable: (@MainActor @Sendable (Float, Float, Float) -> Void)? {
        get { callbackLock.withLock { _onCinematicApertureAvailable } }
        set { callbackLock.withLock { _onCinematicApertureAvailable = newValue } }
    }

    private var _onError: (@MainActor @Sendable (CameraError) -> Void)?
    var onError: (@MainActor @Sendable (CameraError) -> Void)? {
        get { callbackLock.withLock { _onError } }
        set { callbackLock.withLock { _onError = newValue } }
    }

    private var _onRecordingSavedToLibrary: (@MainActor @Sendable () -> Void)?
    var onRecordingSavedToLibrary: (@MainActor @Sendable () -> Void)? {
        get { callbackLock.withLock { _onRecordingSavedToLibrary } }
        set { callbackLock.withLock { _onRecordingSavedToLibrary = newValue } }
    }

    /// Injected saver for the Photo Library write. Defaults to the real
    /// `PHPhotoLibrary`-backed implementation; tests substitute a fake.
    let photoSaver: PhotoLibrarySaver

    // MARK: - Interruption / Runtime-Error Recovery State
    // All three properties below are `sessionQueue`-only. Readers/writers
    // outside `sessionQueue` must hop to it via `sessionQueue.async { ... }`.

    /// True while the session is currently in an interrupted state (audio
    /// device grabbed by another client, phone call, etc.). Set by
    /// `sessionWasInterrupted(_:)` and cleared by the interruption-ended
    /// handler after a successful restart.
    var wasInterrupted = false

    /// True when the interruption cause was a competing audio/video client
    /// (dictation, Siri, another app). In this case, iOS can occasionally
    /// report `session.isRunning == true` while the preview pipeline is still
    /// stale, so interruption-ended may need a controlled stop/start bounce.
    var interruptionNeedsRunningSessionBounce = false

    /// The most recent `RecordingFormat` handed to `configureSession`.
    /// Cached so `.mediaServicesWereReset` recovery can replay the same
    /// configuration without re-plumbing through the view model.
    var lastConfiguredFormat: RecordingFormat?

    /// Test-only counter incremented every time the media-services-reset
    /// recovery path is entered. Not intended for production use.
    var mediaServicesResetRecoveryCount = 0

    /// Foreground-active flag pushed down by the view model via
    /// `setForegroundActive(_:)`. Protected by `callbackLock` because it is
    /// written from `@MainActor` and read from `sessionQueue`.
    private var _isForegroundActive = false

    /// Notification center used to observe capture-session lifecycle
    /// notifications. Injectable so unit tests can post synthetic
    /// notifications to an isolated center without interfering with the
    /// process-wide `.default`.
    let notificationCenter: NotificationCenter

    init(
        photoSaver: PhotoLibrarySaver = DefaultPhotoLibrarySaver(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.photoSaver = photoSaver
        self.notificationCenter = notificationCenter
        super.init()
    }

    deinit {
        // Remove notification observers BEFORE the sessionQueue teardown
        // block is scheduled. Otherwise a notification could be delivered
        // to a partially-deallocated instance while the queue block is
        // still pending. `removeObserver(self)` is synchronous and safe
        // during deinit even when called from an arbitrary thread.
        notificationCenter.removeObserver(self)

        // AVCaptureSession mutations must run on sessionQueue. Capture the
        // session reference locally so the closure does not capture self,
        // which is being deallocated.
        let session = self.session
        sessionQueue.async {
            session.stopRunning()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
        }
    }

    // MARK: - Foreground State

    func setForegroundActive(_ active: Bool) {
        callbackLock.withLock { _isForegroundActive = active }
    }

    /// Reads the foreground-active flag from `sessionQueue`. Non-blocking
    /// because it goes through `callbackLock`, not through the main actor.
    private var isForegroundActive: Bool {
        callbackLock.withLock { _isForegroundActive }
    }

    /// Returns the preferred physical device for a given video mode.
    /// Standard → front wide-angle. Cinematic → front TrueDepth (which has CINE formats).
    /// Finds the front-facing device whose CINE formats are closest to the requested
    /// resolution's standard pixel count. Scans ALL front cameras (TrueDepth, UltraWide, etc.)
    /// so whichever physical camera actually has the best HD or 4K CINE format is used.
    /// e.g. iPhone 17 Pro: UltraWide has 1920x1080 CINE → use UltraWide for HD cinematic.
    ///      iPhone 13:      TrueDepth has 1920x1080 CINE → use TrueDepth for HD cinematic.
    private func bestCinematicDevice(for resolution: VideoResolution) -> AVCaptureDevice? {
        let targetPixels: Int64
        switch resolution {
        case .hd1080p: targetPixels = 1920 * 1080  // 2,073,600
        case .uhd4K: targetPixels = 3840 * 2160  // 8,294,400
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.allVideoDeviceTypes(),
            mediaType: .video,
            position: .front
        )

        var bestDevice: AVCaptureDevice? = nil
        var bestDistance = Int64.max

        for device in discoverySession.devices {
            for fmt in device.formats {
                let isCine: Bool
                if #available(iOS 26.0, *) {
                    isCine = fmt.minSimulatedAperture != 0
                } else {
                    isCine = !fmt.supportedDepthDataFormats.isEmpty
                }
                guard isCine else { continue }
                let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                let distance = abs(Int64(dim.width) * Int64(dim.height) - targetPixels)
                if distance < bestDistance {
                    bestDistance = distance
                    bestDevice = device
                }
            }
        }
        Log.camera.info(
            "bestCinematicDevice(\(resolution.rawValue, privacy: .public)) → \(bestDevice?.localizedName ?? "none", privacy: .public) (distance \(bestDistance, privacy: .public)px)"
        )
        return bestDevice
    }

    /// Returns the preferred physical device for a given video mode and resolution.
    /// Standard → front wide-angle. Cinematic → front camera with the best matching CINE format.
    func preferredDevice(for mode: VideoMode, resolution: VideoResolution = .hd1080p)
        -> AVCaptureDevice?
    {
        switch mode {
        case .standard:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        case .cinematic:
            return bestCinematicDevice(for: resolution)
                ?? AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    /// Discovers the best available camera device for the requested format.
    func discoverCamera(for format: RecordingFormat) -> AVCaptureDevice? {
        preferredDevice(for: format.mode, resolution: format.resolution)
    }

    // MARK: - Audio Input Hot-Swap

    /// Reconfigures the capture session's audio input to match the current
    /// `AVAudioSession` preferred input.
    ///
    /// Called by `CameraViewModel` when `AudioMeterService` detects a route
    /// change. This ensures that the **recorded** audio uses the same mic
    /// the VU meter is monitoring.
    ///
    /// Safe to call while not recording. If called during an active
    /// recording, it's a no-op to avoid corrupting the file.
    ///
    /// **Why not `AVCaptureDevice.default(for: .audio)`?**
    /// That API reads the system default device and ignores any preferred input
    /// set via `AVAudioSession.setPreferredInput()`. It always returns the
    /// built-in mic, so the capture session would record from the wrong device
    /// when an external mic has been selected. Instead, we resolve the active
    /// `AVAudioSession` route input to its matching `AVCaptureDevice` by UID.
    nonisolated func reconfigureAudioInput() {
        sessionQueue.async { [self] in
            guard isSessionConfigured else { return }
            guard !movieFileOutput.isRecording else {
                Log.camera.debug("CameraService: skipping audio input swap — recording in progress")
                return
            }

            // Resolve the AVCaptureDevice that matches the currently active
            // AVAudioSession route input.  Falls back to the system default
            // only if no active route input is found (e.g. no mic at all).
            let newDevice: AVCaptureDevice?
            if let activeInput = AVAudioSession.sharedInstance().currentRoute.inputs.first {
                // Match by UID: AVAudioSessionPortDescription.uid == AVCaptureDevice.uniqueID
                // for built-in and most wired/USB inputs.
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.microphone],
                    mediaType: .audio,
                    position: .unspecified
                )
                newDevice =
                    discovery.devices.first { $0.uniqueID == activeInput.uid }
                    ?? AVCaptureDevice.default(for: .audio)
                Log.camera.debug(
                    "CameraService: active audio route = \(activeInput.portName) (uid=\(activeInput.uid))"
                )
            } else {
                newDevice = AVCaptureDevice.default(for: .audio)
            }

            guard let newDevice else {
                Log.camera.error("CameraService: no audio device available")
                return
            }

            // Skip if already using the same device.
            if let current = audioDevice, current.uniqueID == newDevice.uniqueID {
                Log.camera.debug(
                    "CameraService: audio device unchanged (\(newDevice.localizedName))")
                return
            }

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            // Remove old audio input.
            if let oldInput = audioInput {
                session.removeInput(oldInput)
                audioInput = nil
                Log.camera.debug("CameraService: removed old audio input")
            }

            // Add new audio input.
            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    audioInput = newInput
                    audioDevice = newDevice
                    Log.camera.debug(
                        "CameraService: swapped audio input to \(newDevice.localizedName)")
                } else {
                    Log.camera.error("CameraService: cannot add new audio input")
                }
            } catch {
                Log.camera.error(
                    "CameraService: audio input creation failed – \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Session Lifecycle

    nonisolated func configureSession(format: RecordingFormat = .default) {
        sessionQueue.async {
            guard !self.isSessionConfigured else { return }
            guard self.session.inputs.isEmpty else {
                self.isSessionConfigured = true
                return
            }

            self.session.beginConfiguration()

            // Apply resolution preset — fall back to .high if device doesn't support requested preset.
            let desiredPreset = format.resolution.sessionPreset
            if self.session.canSetSessionPreset(desiredPreset) {
                self.session.sessionPreset = desiredPreset
            } else {
                self.session.sessionPreset = .high
            }

            defer { self.session.commitConfiguration() }

            do {
                var didAddVideoInput = false
                var didAddMovieOutput = false

                // Use discovery session to find the best camera for the requested mode.
                let videoDevice = self.discoverCamera(for: format)

                guard let videoDevice else {
                    self.publishError(.deviceUnavailable)
                    return
                }

                self.videoDevice = videoDevice
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                    self.videoInput = videoInput
                    didAddVideoInput = true
                }

                if let audioDevice = AVCaptureDevice.default(for: .audio) {
                    self.audioDevice = audioDevice
                    let input = try AVCaptureDeviceInput(device: audioDevice)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.audioInput = input
                    }
                }

                if self.session.canAddOutput(self.movieFileOutput) {
                    self.session.addOutput(self.movieFileOutput)
                    didAddMovieOutput = true
                }

                guard didAddVideoInput && didAddMovieOutput else {
                    self.publishError(.inputConfigurationFailed)
                    return
                }

                // Set cinematic format explicitly when using TrueDepth camera.
                // For standard mode, the session preset handles resolution.
                if format.mode == .cinematic {
                    if let cinematicFormat = self.findCinematicFormat(
                        for: videoDevice, resolution: format.resolution, frameRate: format.frameRate
                    ) {
                        do {
                            try videoDevice.lockForConfiguration()
                            videoDevice.activeFormat = cinematicFormat
                            videoDevice.unlockForConfiguration()
                            if #available(iOS 26.0, *), videoInput.isCinematicVideoCaptureSupported
                            {
                                self.enableCinematicCapture(on: videoInput)
                            }
                        } catch {
                            self.publishError(.formatUnavailable(error.localizedDescription))
                            self.disableCinematicCapture()
                        }
                    } else {
                        Log.camera.info("No cinematic format found, falling back to standard.")
                        self.disableCinematicCapture()
                    }
                } else {
                    self.disableCinematicCapture()
                }

                // Apply frame rate after inputs/outputs are wired.
                self.applyFrameRate(format.frameRate, to: videoDevice)

                self.isSessionConfigured = true
                // Cache the format so `.mediaServicesWereReset` recovery can
                // rebuild the same configuration without re-plumbing through
                // the view model.
                self.lastConfiguredFormat = format

                // Register interruption / runtime-error observers now that
                // the session is fully wired. Registering earlier would risk
                // receiving callbacks for a partially-configured session.
                self.registerSessionObservers()

                // Dump all camera formats on first configure — visible in Xcode console.
                self.logAllCameraFormats()

                // Query device capabilities (includes mode-specific format support).
                let capabilities = self.queryDeviceCapabilities()

                Task { @MainActor in
                    self.onDeviceCapabilitiesQueried?(capabilities)
                }
            } catch {
                self.publishError(.sessionConfigurationFailed(error.localizedDescription))
            }
        }
    }

    nonisolated func startSession() {
        sessionQueue.async {
            guard self.isSessionConfigured else {
                Log.camera.info(
                    "\(Log.ts(), privacy: .public) startSession skipped (not configured)")
                self.publishSessionRunningState(false)
                return
            }

            guard !self.session.isRunning else {
                Log.camera.info(
                    "\(Log.ts(), privacy: .public) startSession no-op (already running)")
                self.publishSessionRunningState(true)
                return
            }
            Log.camera.info("\(Log.ts(), privacy: .public) startSession begin")
            self.session.startRunning()
            Log.camera.info(
                "\(Log.ts(), privacy: .public) startSession end isRunning=\(self.session.isRunning, privacy: .public)"
            )
            self.publishSessionRunningState(true)
        }
    }

    nonisolated func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            Log.camera.info("\(Log.ts(), privacy: .public) stopSession begin")
            self.session.stopRunning()
            Log.camera.info(
                "\(Log.ts(), privacy: .public) stopSession end isRunning=\(self.session.isRunning, privacy: .public)"
            )
            self.publishSessionRunningState(false)
        }
    }

    // MARK: - Callback Publishing

    func publishRecordingState(_ isRecording: Bool) {
        Task { @MainActor in
            self.onRecordingStateChanged?(isRecording)
        }
    }

    func publishError(_ error: CameraError) {
        Log.camera.error("\(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            self.onError?(error)
        }
    }

    func publishSessionRunningState(_ isRunning: Bool) {
        Task { @MainActor in
            self.onSessionRunningStateChanged?(isRunning)
        }
    }

    func publishLockOutcome(
        _ outcome: FocusExposureLockOutcome,
        completion: (@MainActor @Sendable (FocusExposureLockOutcome) -> Void)?
    ) {
        guard let completion else { return }
        Task { @MainActor in
            completion(outcome)
        }
    }

    // MARK: - Interruption / Runtime-Error Observers

    /// Registers observers for the three `AVCaptureSession` lifecycle
    /// notifications required for reliable interruption recovery.
    ///
    /// Called from `configureSession` on the `sessionQueue`. Uses
    /// selector-based observation so `deinit`'s `removeObserver(self)` (on
    /// the notification center) cleanly deregisters all three at once.
    ///
    /// Filtering by `object: session` ensures we only receive notifications
    /// from our own capture session, not other sessions in the process
    /// (e.g. from `AVCaptureMetadataOutput` or a background HLS session).
    ///
    /// **Idempotency**: `NotificationCenter` does not de-duplicate
    /// `addObserver` calls by (self, selector, name, object), so we guard
    /// re-entry with a one-shot flag. `configureSession` short-circuits on
    /// its second call via `isSessionConfigured`, so under normal flow this
    /// is only called once, but the guard makes the media-services-reset
    /// recovery path safe when it calls `configureSession` again.
    ///
    /// Exposed at `internal` so unit tests can register observers on a
    /// `CameraService` instance without needing hardware to complete
    /// `configureSession`.
    func registerSessionObservers() {
        guard !didRegisterSessionObservers else { return }
        didRegisterSessionObservers = true

        notificationCenter.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    /// One-shot latch so `registerSessionObservers` is safe to call more
    /// than once per instance. `sessionQueue`-only.
    var didRegisterSessionObservers = false

    /// Handler for `AVCaptureSession.wasInterruptedNotification`.
    ///
    /// Delivered on the posting thread — hops to `sessionQueue` immediately
    /// so all state access is serialized under the class's Sendable contract.
    @objc func sessionWasInterrupted(_ notification: Notification) {
        // `Notification` is not Sendable; extract the sendable payload here
        // on the posting thread before hopping queues.
        let reasonRaw = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
        sessionQueue.async { [weak self] in
            self?.handleInterruption(reasonRaw: reasonRaw)
        }
    }

    /// Reason-branching logic for `sessionWasInterrupted`. Exposed at
    /// `internal` so tests can drive the branches directly without
    /// building a real `Notification`.
    func handleInterruption(reasonRaw: Int?) {
        let reason = reasonRaw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))

        switch reason {
        case .audioDeviceInUseByAnotherClient,
            .videoDeviceInUseByAnotherClient:
            // Another client (dictation, Siri, phone, another app) took the
            // hardware. Mark for restart when interruption ends.
            wasInterrupted = true
            interruptionNeedsRunningSessionBounce = true
            Log.camera.info(
                "\(Log.ts(), privacy: .public) AVCaptureSession interrupted: reason=\(reason?.debugName ?? "unknown", privacy: .public)"
            )

        case .videoDeviceNotAvailableInBackground:
            // App was backgrounded. Scene phase / onDisappear owns this;
            // do NOT set wasInterrupted so we don't auto-restart on
            // .interruptionEnded when the app returns to foreground —
            // onAppear will handle that path.
            interruptionNeedsRunningSessionBounce = false
            Log.camera.info(
                "AVCaptureSession interrupted: reason=videoDeviceNotAvailableInBackground (ignoring — scene phase owns restart)"
            )

        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            // iPad Slide Over / Split View. User-initiated multitasking —
            // do not auto-restart, iOS controls this lifecycle.
            interruptionNeedsRunningSessionBounce = false
            Log.camera.info(
                "AVCaptureSession interrupted: reason=videoDeviceNotAvailableWithMultipleForegroundApps (ignoring — user multitasking)"
            )

        case .videoDeviceNotAvailableDueToSystemPressure:
            // Thermal or performance throttle. Surface to the user so they
            // know the camera stopped for a reason outside their control.
            wasInterrupted = true
            interruptionNeedsRunningSessionBounce = false
            Log.camera.error(
                "AVCaptureSession interrupted: reason=videoDeviceNotAvailableDueToSystemPressure")
            publishError(
                .sessionRuntimeError(
                    "System pressure paused the camera. Try again when the device cools down."))

        case .none, .some:
            // Unknown or future reason. Set defensively so
            // `.interruptionEnded` can attempt a restart if the view is
            // still on-screen.
            wasInterrupted = true
            interruptionNeedsRunningSessionBounce = false
            Log.camera.info(
                "AVCaptureSession interrupted: reason=unknown(\(reasonRaw ?? -1, privacy: .public))"
            )
        }
    }

    /// Handler for `AVCaptureSession.interruptionEndedNotification`.
    ///
    /// Attempts to restart the session, but only when every guard passes:
    ///   1. We set `wasInterrupted` (i.e. we own the restart).
    ///   2. The session is fully configured.
    ///   3. The camera view is still on-screen (`isForegroundActive`),
    ///      which is driven by `CameraView.onAppear`/`onDisappear` and
    ///      therefore also flips false when SwiftUI tears the view down
    ///      on app backgrounding. This flag is authoritative for both
    ///      "view visible" and "app in foreground".
    ///   4. If already running when interruption ends, optionally performs
    ///      a controlled stop/start bounce for competing-client interruptions.
    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            self?.handleInterruptionEnded()
        }
    }

    /// Restart-attempt logic for `sessionInterruptionEnded`. Exposed at
    /// `internal` so tests can drive the guards directly.
    func handleInterruptionEnded() {
        guard wasInterrupted else { return }
        guard isSessionConfigured else {
            Log.camera.info(
                "\(Log.ts(), privacy: .public) AVCaptureSession interruption ended — skipping restart (not configured)"
            )
            return
        }
        guard isForegroundActive else {
            Log.camera.info(
                "\(Log.ts(), privacy: .public) AVCaptureSession interruption ended — skipping restart (view not foreground-active)"
            )
            return
        }
        guard !session.isRunning else {
            if interruptionNeedsRunningSessionBounce {
                // Recover from the edge case where AVCaptureSession reports
                // running after interruption, but preview frames are stale.
                Log.camera.info(
                    "\(Log.ts(), privacy: .public) AVCaptureSession interruption ended — already running, forcing restart bounce"
                )
                session.stopRunning()
                publishSessionRunningState(false)
                session.startRunning()
                if session.isRunning {
                    Log.camera.info(
                        "\(Log.ts(), privacy: .public) AVCaptureSession restart bounce succeeded")
                    publishSessionRunningState(true)
                } else {
                    Log.camera.error(
                        "\(Log.ts(), privacy: .public) AVCaptureSession restart bounce failed")
                }
            } else {
                // Rare: session recovered on its own before we could act.
                Log.camera.info(
                    "\(Log.ts(), privacy: .public) AVCaptureSession interruption ended — already running, clearing flag"
                )
            }
            interruptionNeedsRunningSessionBounce = false
            wasInterrupted = false
            return
        }

        Log.camera.info(
            "\(Log.ts(), privacy: .public) AVCaptureSession interruption ended — restarting")
        let signpostID = Log.cameraSignposter.makeSignpostID()
        let state = Log.cameraSignposter.beginInterval("CaptureSessionRestart", id: signpostID)
        session.startRunning()
        Log.cameraSignposter.endInterval("CaptureSessionRestart", state)
        interruptionNeedsRunningSessionBounce = false
        wasInterrupted = false
        if session.isRunning {
            Log.camera.info(
                "\(Log.ts(), privacy: .public) AVCaptureSession startRunning succeeded (post-interruption)"
            )
            publishSessionRunningState(true)
        } else {
            Log.camera.error(
                "\(Log.ts(), privacy: .public) AVCaptureSession startRunning failed (post-interruption)"
            )
        }
    }

    /// Handler for `AVCaptureSession.runtimeErrorNotification`.
    ///
    /// Recovers from `.mediaServicesWereReset` by tearing down the session
    /// and re-running `configureSession` with the last-known format. Other
    /// errors are surfaced through `publishError` — the session is not
    /// restarted automatically because the underlying cause is not
    /// predictable.
    @objc private func sessionRuntimeError(_ notification: Notification) {
        // Extract sendable payload on the posting thread.
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        let localized = error?.localizedDescription ?? "unknown"
        let code = error?.code
        sessionQueue.async { [weak self] in
            self?.handleRuntimeError(code: code, localized: localized)
        }
    }

    /// Branch-dispatch logic for `sessionRuntimeError`. Exposed at
    /// `internal` so tests can drive each branch without building an
    /// `AVError` `Notification`.
    func handleRuntimeError(code: AVError.Code?, localized: String) {
        switch code {
        case .some(.mediaServicesWereReset):
            Log.camera.error("AVCaptureSession runtime error: mediaServicesWereReset — recovering")
            recoverFromMediaServicesReset()

        case .some(.sessionWasInterrupted):
            // Defensive: iOS should have posted .wasInterrupted first, but
            // occasionally a runtime error lands here too. Treat as an
            // interruption event.
            Log.camera.notice(
                "AVCaptureSession runtime error: sessionWasInterrupted (treating as interruption)")
            wasInterrupted = true

        default:
            Log.camera.error(
                "AVCaptureSession runtime error: \(localized, privacy: .public) (no auto-recovery)")
            publishError(.sessionRuntimeError(localized))
        }
    }

    /// Rebuilds the session after `.mediaServicesWereReset`. All outputs
    /// are invalidated by this event, so a simple `startRunning()` is not
    /// enough — the session must be fully re-plumbed.
    ///
    /// Exposed at `internal` so tests can assert the recovery counter and
    /// state transitions without building a real `Notification`.
    func recoverFromMediaServicesReset() {
        mediaServicesResetRecoveryCount += 1
        let format = lastConfiguredFormat ?? .default

        // Tear down: mark unconfigured and drop all existing inputs/outputs
        // so `configureSession`'s `session.inputs.isEmpty` guard passes.
        isSessionConfigured = false
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        session.commitConfiguration()

        // Reconfigure + restart. Both hop back onto `sessionQueue` via
        // their own `async` blocks; we're already there, but that's fine —
        // dispatch on a serial queue from the same queue just enqueues.
        configureSession(format: format)
        startSession()
    }
}

// MARK: - AVCaptureSession.InterruptionReason Debug Names

extension AVCaptureSession.InterruptionReason {
    /// Compact stable name used in log statements. `debugDescription` on
    /// the raw type is not guaranteed to be stable across iOS versions.
    fileprivate var debugName: String {
        switch self {
        case .videoDeviceNotAvailableInBackground: return "videoDeviceNotAvailableInBackground"
        case .audioDeviceInUseByAnotherClient: return "audioDeviceInUseByAnotherClient"
        case .videoDeviceInUseByAnotherClient: return "videoDeviceInUseByAnotherClient"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "videoDeviceNotAvailableWithMultipleForegroundApps"
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "videoDeviceNotAvailableDueToSystemPressure"
        case .sensitiveContentMitigationActivated: return "sensitiveContentMitigationActivated"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
