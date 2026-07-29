// May 31, 2026 - 2:30am - GitHub Copilot (Claude Opus 4.7)
// June 13, 2026 - GitHub Copilot (Claude Sonnet 4.5) - Added recording timer with Combine
// July 8, 2026 - GitHub Copilot (Claude Opus 4.7) - resetTeleprompterPosition no longer toggles isScrolling
import AVFoundation
import SwiftUI

enum CameraSheetRoute: String, Identifiable, Sendable {
    case formatPanel
    case composeScript
    case settings
    case recordingsLibrary

    var id: String { rawValue }
}

enum CameraMode: Equatable, Sendable {
    case camera
    case compose
}

enum CameraLockStatus: Equatable, Sendable {
    case auto
    case aeAfLocked
    case aeLocked
    case afLocked
    case unsupported

    var isLocked: Bool {
        switch self {
        case .aeAfLocked, .aeLocked, .afLocked:
            return true
        case .auto, .unsupported:
            return false
        }
    }

    var text: String {
        switch self {
        case .auto:
            return "AUTO"
        case .aeAfLocked:
            return "AE/AF LOCK"
        case .aeLocked:
            return "AE LOCK"
        case .afLocked:
            return "AF LOCK"
        case .unsupported:
            return "LOCK UNAVAILABLE"
        }
    }

    /// Two-part display label for stacked badge layout.
    /// `top` is the sensor abbreviation; `bottom` is the state word (or `nil` for single-line).
    var displayParts: (top: String, bottom: String?) {
        switch self {
        case .auto:          return ("AUTO",  nil)
        case .aeAfLocked:    return ("AE/AF", "Lock")
        case .aeLocked:      return ("AE",    "Lock")
        case .afLocked:      return ("AF",    "Lock")
        case .unsupported:   return ("LOCK",  "UNAVAIL")
        }
    }
}

/// Central state owner for the camera screen.
///
/// **@MainActor**: All published properties drive SwiftUI views, so the entire
/// class is main-actor-isolated. Camera hardware calls go through `CameraService`
/// which runs them on its own serial queue.
///
/// **Modal queue pattern**: SwiftUI allows only one `.sheet` presenter at a time.
/// Sheet presentation is delegated to `ModalQueue`, which queues a second
/// request while one is active and dequeues it on dismissal. This prevents the
/// "sheet not presented" bug that occurs with rapid modal switching.
///
/// **Callback binding**: `bindCallbacks()` connects `CameraService` closures to
/// observable properties at init time, keeping the service layer protocol-free.
@MainActor
@Observable
final class CameraViewModel {
    var config = TeleprompterConfig.default
    var isRecording = false
    var isScrolling = false
    /// Drives the recording duration display. Read via `viewModel.recordingTimer.duration`.
    let recordingTimer = RecordingTimer()

    var cameraError: CameraError?
    var lockStatus: CameraLockStatus = .auto
    var isCameraReady = false
    /// True while the camera view is on-screen (between `onAppear` and
    /// `onDisappear`). Read from `sessionQueue` by the camera service to
    /// decide whether it is safe to auto-restart the capture session after
    /// an interruption. Defaults to `false` so the service is conservative
    /// before the view has appeared.
    private(set) var isForegroundActive: Bool = false
    /// Serializes sheet presentation. The active sheet is bound via
    /// `viewModel.modalQueue.activeSheet`.
    ///
    /// Declared `var` (not `let`) so SwiftUI `@Bindable` can build writable
    /// key paths through it (e.g. `$viewModel.modalQueue.activeSheet`). The
    /// class is never reassigned — this is a Swift 6 requirement for chained
    /// bindings, not an API change.
    var modalQueue = ModalQueue()
    /// Compose sheet is presented as a fullScreenCover to prevent
    /// iOS sheet presentation from rescaling the camera preview.
    var showComposeSheet = false
    var cameraMode: CameraMode = .camera
    /// Warning banner for format panel locked during recording.
    var showFormatLockedWarning = false
    /// Bumped to signal the overlay to reset position (zero manualOffset).
    var teleprompterResetToken: Int = 0
    /// Current recording format (resolution + FPS). Persisted across launches.
    var recordingFormat: RecordingFormat
    /// Device capabilities (mode support, resolution/fps per mode).
    var deviceCapabilities: DeviceCapabilities = DeviceCapabilities(
        supportsCinematicMode: false,
        standardFormats: [RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .standard)],
        cinematicFormats: []
    )
    /// Aperture range reported by the active cinematic format (iOS 26+ only).
    /// Nil when cinematic mode is inactive or device/OS does not support it.
    var cinematicApertureRange: ClosedRange<Float>? = nil
    /// Current simulated aperture value shown in the aperture slider.
    var cinematicSimulatedAperture: Float = 2.0

    // MARK: - Audio Metering

    /// Owns all audio-metering state and the `AudioMeterService` lifecycle.
    /// The view reads levels/warnings through `viewModel.audioMeter`.
    ///
    /// Declared `var` (not `let`) so SwiftUI `@Bindable` can build writable
    /// key paths through it (e.g. `$viewModel.audioMeter.showAudioSourcePicker`).
    /// The class is never reassigned.
    var audioMeter: AudioMeterViewModel

    // MARK: - Direct Player State

    /// Owns the recordings carousel and direct-player state. The view reads
    /// through `viewModel.recordings`.
    ///
    /// Declared `var` (not `let`) so SwiftUI `@Bindable` can build writable
    /// key paths through it (e.g. `$viewModel.recordings.showDirectPlayer`).
    /// The class is never reassigned.
    var recordings = RecordingsGallery()

    let cameraService: CameraServiceProtocol
    private let permissionService: PermissionService
    /// Refreshes the carousel whenever the Photo Library changes (own saves,
    /// Photos.app deletes, iCloud sync). Started in onAppear, stopped in
    /// onDisappear. Complements onRecordingSavedToLibrary from CameraService.
    @ObservationIgnored private let photoLibraryMonitor = PhotoLibraryChangeMonitor()
    /// Persists teleprompter style settings to UserDefaults.
    @ObservationIgnored private let styleStore = TeleprompterStyleStore()



    init(
        cameraService: CameraServiceProtocol = CameraService(),
        permissionService: PermissionService = PermissionService()
    ) {
        self.cameraService = cameraService
        self.permissionService = permissionService
        self.recordingFormat = RecordingFormat.loadSaved()
        self.audioMeter = AudioMeterViewModel(cameraService: cameraService)
        config = styleStore.applyingSaved(to: config)
        bindCallbacks()
        // `self` is fully initialized here, so the audio meter can safely read
        // the live recording flag through this closure.
        audioMeter.isRecording = { [weak self] in self?.isRecording ?? false }
    }

    var session: AVCaptureSession { cameraService.previewSession }

    func onAppear() {
        Log.viewmodel.info("\(Log.ts(), privacy: .public) CameraViewModel onAppear")
        isCameraReady = false
        isForegroundActive = true
        // Notify the service before startSession so the interruption-ended
        // handler will restart the session if it fires during startup.
        cameraService.setForegroundActive(true)
        // Permissions are already granted by the onboarding page.
        cameraService.configureSession(format: recordingFormat)
        cameraService.startSession()
        // Wire external-display service so HDMI/AirPlay gets a clean feed.
        ExternalDisplayService.shared.configure(session: cameraService.previewSession)
        // Observe photo-library changes so the carousel refreshes on external
        // deletes, iCloud sync, etc. Debounced to coalesce bursts.
        photoLibraryMonitor.start { [weak self] in
            self?.recordings.refreshInBackground()
        }
        // Device capabilities are received via onDeviceCapabilitiesQueried callback
        // after configureSession completes on the session queue.
        // Audio metering attaches in onSessionRunningStateChanged callback.
        Task { await recordings.prefetch() }
    }

    func onDisappear() {
        Log.viewmodel.info("\(Log.ts(), privacy: .public) CameraViewModel onDisappear")
        recordingTimer.stop()
        audioMeter.stop()
        // Clear the foreground flag BEFORE stopping the session so any
        // interruption-ended notification racing with teardown will not
        // attempt an auto-restart.
        cameraService.setForegroundActive(false)
        cameraService.stopSession()
        photoLibraryMonitor.stop()
        isCameraReady = false
        isForegroundActive = false
    }

    func toggleRecording() {
        guard isCameraReady else { return }

        if isRecording {
            recordingTimer.stop()
            cameraService.stopRecording()
            Log.viewmodel.info("toggleRecording -> stopped")
        } else {
            recordingTimer.start()
            cameraService.startRecording()
            Log.viewmodel.info("toggleRecording -> started")
        }
    }

    func toggleScrolling() {
        isScrolling.toggle()
        Log.viewmodel.debug("toggleScrolling -> \(self.isScrolling, privacy: .public)")
    }

    func openPhotoLibrary() {
        guard !isRecording else { return }
        openDirectPlayer()
    }

    /// Opens the direct player on the most recent recording.
    /// If the latest recording isn't ready yet, falls back to the library sheet.
    func openDirectPlayer() {
        guard !isRecording else { return }
        if recordings.latestRecording != nil {
            recordings.showDirectPlayer = true
        } else {
            // Fallback: no recording exists yet
            modalQueue.present(.recordingsLibrary)
        }
    }

    func openCompose() {
        guard !isRecording else { return }
        Log.viewmodel.info("\(Log.ts(), privacy: .public) openCompose")
        cameraMode = .compose
        showComposeSheet = true
    }

    func dismissComposeSheet() {
        Log.viewmodel.info("\(Log.ts(), privacy: .public) dismissComposeSheet")
        showComposeSheet = false
        cameraMode = .camera
    }

    func openSettings() {
        guard !isRecording else { return }
        modalQueue.present(.settings)
    }



    func openFormatPanel() {
        // Gate: Cannot change format while recording
        guard !isRecording else {
            withAnimation(Theme.panelSpring) {
                showFormatLockedWarning = true
            }
            return
        }// Sheet to change format
        modalQueue.present(.formatPanel)
    }



    func dismissActiveSheet() {
        modalQueue.dismissActive()
    }

    func handleSheetStateChanged(_ newValue: CameraSheetRoute?) {
        guard newValue == nil else { return }

        if modalQueue.lastPresentedSheet == .composeScript {
            cameraMode = .camera
        }

        modalQueue.finishDismissal()
    }



    func updateScriptText(_ text: String) {
        Log.viewmodel.debug("updateScriptText len=\(text.count, privacy: .public)")
        config.text = text
        styleStore.save(config)
    }

    /// Applies and clamps new style settings, then persists them.
    func updateTeleprompterStyle(_ updated: TeleprompterConfig) {
        // Preserve the current script text — only style fields change here.
        var next = updated.clamped
        next.text = config.text
        config = next
        styleStore.save(config)
        Log.viewmodel.debug("updateTeleprompterStyle fontSize=\(Int(self.config.fontSize), privacy: .public) speed=\(Int(self.config.speedPointsPerSecond), privacy: .public) color=\(self.config.textColor.rawValue, privacy: .public) bgOpacity=\(self.config.backgroundOpacity, privacy: .public)")
    }

    /// Cycles to the next text alignment option.
    @MainActor
    func cycleTextAlignment() {
        config.textAlignment = config.textAlignment.next
        styleStore.save(config)
        Log.viewmodel.debug("Text alignment cycled to: \(self.config.textAlignment.rawValue, privacy: .public)")
    }

    /// Resets the teleprompter to its centered starting position.
    /// Independent of scroll play/pause state — used to "find" the script if
    /// it has drifted off-screen. If auto-scroll is running it continues to run,
    /// but restarts from the newly-centered position (overlay's resetScrollPosition
    /// resets scrollStartTime so elapsed begins at 0 again).
    func resetTeleprompterPosition() {
        teleprompterResetToken += 1
        Log.viewmodel.debug("resetTeleprompterPosition token=\(self.teleprompterResetToken, privacy: .public) isScrolling=\(self.isScrolling, privacy: .public)")
    }

    func focus(at devicePoint: CGPoint) {
        cameraService.focus(at: devicePoint)
    }

    func lockFocusExposure(at devicePoint: CGPoint) {
        cameraService.lockFocusExposure(at: devicePoint) { [weak self] outcome in
            self?.lockStatus = CameraLockStatus(outcome: outcome)
        }
    }

    func unlockFocusExposure() {
        cameraService.unlockFocusExposure()
        lockStatus = .auto
    }

    func setSimulatedAperture(_ value: Float) {
        cinematicSimulatedAperture = value
        cameraService.setSimulatedAperture(value)
    }

    func adjustExposure(by delta: Float) {
        cameraService.adjustExposure(by: delta)
    }

    /// Sets exposure bias to an absolute value. Use for reset — avoids delta drift.
    func setExposure(to value: Float) {
        cameraService.setExposure(to: value)
    }

    // MARK: - Recording Format

    /// Applies a new recording format to the camera. No-op if recording.
    func updateRecordingFormat(_ format: RecordingFormat) {
        guard !isRecording else { return }
        Log.viewmodel.info("updateRecordingFormat res=\(format.resolution.rawValue, privacy: .public) fps=\(format.frameRate.rawValue, privacy: .public) mode=\(format.mode.rawValue, privacy: .public)")
        cameraService.applyFormat(format)
    }

    private func bindCallbacks() {
        cameraService.onRecordingStateChanged = { [weak self] isRecording in
            guard let self else { return }
            self.isRecording = isRecording
            // When recording stops the video is saved to the photo library.
            // Refresh the latest recording so the direct player is ready immediately.
            if !isRecording {
                self.recordings.refreshInBackground()
            }
        }

        // Fires the instant PhotoKit actually persists the new asset — closes
        // the race where onRecordingStateChanged fires before the save is done.
        cameraService.onRecordingSavedToLibrary = { [weak self] in
            self?.recordings.refreshInBackground()
        }

        cameraService.onSessionRunningStateChanged = { [weak self] isRunning in
            guard let self else { return }
            self.isCameraReady = isRunning
            // Attach audio metering once the session is fully configured
            // and running. Attaching earlier fails because the session
            // hasn't added its audio input yet. `setup()` is idempotent.
            if isRunning {
                self.audioMeter.setup()
                // If the meter deferred its own post-interruption restart
                // (see AudioMeterService.pendingReconnectAfterInterruption),
                // this is the confirmed signal that it's now safe to do so
                // without racing this same restart. No-op if nothing pending.
                self.audioMeter.reconnectIfPending()
            }
        }

        cameraService.onFormatApplied = { [weak self] applied in
            guard let self else { return }
            self.recordingFormat = applied
            applied.save()
            Log.viewmodel.info("format applied res=\(applied.resolution.rawValue, privacy: .public) fps=\(applied.frameRate.rawValue, privacy: .public)")
        }

        cameraService.onDeviceCapabilitiesQueried = { [weak self] capabilities in
            guard let self else { return }
            self.deviceCapabilities = capabilities
            Log.viewmodel.info("device capabilities cine=\(capabilities.supportsCinematicMode, privacy: .public)")
            
            // Auto-adjust format if current selection isn't supported.
            if !capabilities.isSupported(self.recordingFormat) {
                let adjusted = capabilities.adjusted(self.recordingFormat)
                self.recordingFormat = adjusted
                adjusted.save()
                Log.viewmodel.notice("format auto-adjusted to res=\(adjusted.resolution.rawValue, privacy: .public) fps=\(adjusted.frameRate.rawValue, privacy: .public) mode=\(adjusted.mode.rawValue, privacy: .public)")
            }
        }

        cameraService.onCinematicApertureAvailable = { [weak self] minAp, maxAp, defAp in
            guard let self else { return }
            if minAp == 0 {
                self.cinematicApertureRange = nil
                Log.viewmodel.info("Cinematic aperture: unavailable")
            } else {
                // Clamp the lower bound to f/5.6 — the app intentionally avoids
                // very shallow DoF settings (f/1.9–f/4.5) which look unnatural
                // for teleprompter/presenter use. The hardware minimum is preserved
                // as the floor in case a future device reports a higher minimum.
                let appMin: Float = max(minAp, 5.6)
                self.cinematicApertureRange = appMin...maxAp
                self.cinematicSimulatedAperture = appMin   // default to f/5.6
                Log.viewmodel.info("Cinematic aperture range f/\(appMin, privacy: .public)–f/\(maxAp, privacy: .public) (hw min f/\(minAp, privacy: .public), default f/\(defAp, privacy: .public))")
            }
        }

        cameraService.onError = { [weak self] error in
            self?.cameraError = error
        }
    }
}

private extension CameraLockStatus {
    init(outcome: FocusExposureLockOutcome) {
        switch outcome {
        case .afAeLocked:
            self = .aeAfLocked
        case .aeLocked:
            self = .aeLocked
        case .afLocked:
            self = .afLocked
        case .unsupported:
            self = .unsupported
        }
    }
}
