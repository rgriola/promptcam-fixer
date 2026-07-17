// May 31, 2026 - 2:30am - GitHub Copilot (Claude Opus 4.7)
// June 13, 2026 - GitHub Copilot (Claude Sonnet 4.5) - Added recording timer with Combine
// July 8, 2026 - GitHub Copilot (Claude Opus 4.7) - resetTeleprompterPosition no longer toggles isScrolling
import AVFoundation
import Photos
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
    /// Serializes sheet presentation. The active sheet is bound via
    /// `viewModel.modalQueue.activeSheet`.
    let modalQueue = ModalQueue()
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
    let audioMeter: AudioMeterViewModel

    // MARK: - Direct Player State

    /// The most recently recorded video, pre-fetched so the player opens immediately.
    var latestRecording: Recording?
    /// Resolved URL for `latestRecording` — ready before the player opens.
    var latestVideoURL: URL?
    /// First 8 recordings for the carousel, pre-warmed by PHCachingImageManager.
    var recentRecordings: [Recording] = []
    /// Controls direct player sheet presentation.
    var showDirectPlayer = false

    @ObservationIgnored private let recordingsService = RecordingsService()

    // MARK: - Style Persistence Keys
    private enum StyleKey {
        static let fontSize   = "tp.fontSize"
        static let speed      = "tp.speed"
        static let textColor  = "tp.textColor"
        static let bgOpacity  = "tp.bgOpacity"
        static let alignment  = "tp.alignment"
        static let scriptText = "tp.scriptText"
    }

    let cameraService: CameraServiceProtocol
    private let permissionService: PermissionService
    /// Refreshes the carousel whenever the Photo Library changes (own saves,
    /// Photos.app deletes, iCloud sync). Started in onAppear, stopped in
    /// onDisappear. Complements onRecordingSavedToLibrary from CameraService.
    @ObservationIgnored private let photoLibraryMonitor = PhotoLibraryChangeMonitor()



    init(
        cameraService: CameraServiceProtocol = CameraService(),
        permissionService: PermissionService = PermissionService()
    ) {
        self.cameraService = cameraService
        self.permissionService = permissionService
        self.recordingFormat = RecordingFormat.loadSaved()
        self.audioMeter = AudioMeterViewModel(cameraService: cameraService)
        loadStylePreferences()
        bindCallbacks()
        // `self` is fully initialized here, so the audio meter can safely read
        // the live recording flag through this closure.
        audioMeter.isRecording = { [weak self] in self?.isRecording ?? false }
    }

    var session: AVCaptureSession { cameraService.previewSession }

    func onAppear() {
        isCameraReady = false
        // Permissions are already granted by the onboarding page.
        cameraService.configureSession(format: recordingFormat)
        cameraService.startSession()
        // Wire external-display service so HDMI/AirPlay gets a clean feed.
        ExternalDisplayService.shared.configure(session: cameraService.previewSession)
        // Observe photo-library changes so the carousel refreshes on external
        // deletes, iCloud sync, etc. Debounced to coalesce bursts.
        photoLibraryMonitor.start { [weak self] in
            self?.refreshLatestRecording()
        }
        // Device capabilities are received via onDeviceCapabilitiesQueried callback
        // after configureSession completes on the session queue.
        // Audio metering attaches in onSessionRunningStateChanged callback.
        Task { await prefetchLatestRecording() }
    }

    func onDisappear() {
        recordingTimer.stop()
        audioMeter.stop()
        cameraService.stopSession()
        photoLibraryMonitor.stop()
        isCameraReady = false
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
        if latestRecording != nil {
            showDirectPlayer = true
        } else {
            // Fallback: no recording exists yet
            modalQueue.present(.recordingsLibrary)
        }
    }

    /// Fetches the latest recording and pre-resolves its URL so the player
    /// opens without delay. Loads ALL recordings for the carousel — Recording
    /// objects are lightweight PHAsset wrappers (~100 bytes each). Only the
    /// first window of thumbnails is pre-warmed; the rest load on demand as
    /// the user swipes.
    func prefetchLatestRecording() async {
        let latest = recordingsService.fetchLatestRecording()
        latestRecording = latest

        // Resolve URL in background so it's ready when player opens.
        if let latest {
            latestVideoURL = await recordingsService.resolveURL(for: latest)
        }

        // Fetch all recordings — no limit. PHAsset references are tiny.
        let all = await recordingsService.fetchAllRecordings()
        recentRecordings = all

        // Pre-warm thumbnails for the first visible window only.
        let warmIDs = all.prefix(8).map(\.id)
        if !warmIDs.isEmpty {
            let carouselSize = CGSize(width: 144, height: 144)
            recordingsService.startCaching(ids: Array(warmIDs), targetSize: carouselSize)
        }
    }

    /// Pre-warms carousel thumbnails in a sliding window around the given
    /// recording. Call this when the user navigates to a new item so adjacent
    /// thumbnails are ready before they scroll into view.
    ///
    /// Window default expanded from ±4 to ±6 (Phase 2) so a full flick to a
    /// far-away cell doesn't outrun the pre-warm on older devices (A11/A12)
    /// where thumbnail decode is 60–100ms per cell.
    func warmCarouselCache(around recording: Recording, windowSize: Int = 6) {
        guard let index = recentRecordings.firstIndex(where: { $0.id == recording.id }) else { return }
        let lo = max(0, index - windowSize)
        let hi = min(recentRecordings.count - 1, index + windowSize)
        let ids = recentRecordings[lo...hi].map(\.id)
        recordingsService.startCaching(ids: ids, targetSize: CGSize(width: 144, height: 144))
    }

    /// Call after a recording finishes saving to refresh the player state.
    func refreshLatestRecording() {
        Task { await prefetchLatestRecording() }
    }

    

    func openCompose() {
        guard !isRecording else { return }
        cameraMode = .compose
        showComposeSheet = true
    }

    func dismissComposeSheet() {
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
        saveStylePreferences()
    }

    /// Applies and clamps new style settings, then persists them.
    func updateTeleprompterStyle(_ updated: TeleprompterConfig) {
        // Preserve the current script text — only style fields change here.
        var next = updated.clamped
        next.text = config.text
        config = next
        saveStylePreferences()
        Log.viewmodel.debug("updateTeleprompterStyle fontSize=\(Int(self.config.fontSize), privacy: .public) speed=\(Int(self.config.speedPointsPerSecond), privacy: .public) color=\(self.config.textColor.rawValue, privacy: .public) bgOpacity=\(self.config.backgroundOpacity, privacy: .public)")
    }

    /// Cycles to the next text alignment option.
    @MainActor
    func cycleTextAlignment() {
        config.textAlignment = config.textAlignment.next
        saveStylePreferences()
        Log.viewmodel.debug("Text alignment cycled to: \(self.config.textAlignment.rawValue, privacy: .public)")
    }

    // MARK: - Style Persistence

    private func saveStylePreferences() {
        let ud = UserDefaults.standard
        ud.set(config.fontSize,                   forKey: StyleKey.fontSize)
        ud.set(config.speedPointsPerSecond,        forKey: StyleKey.speed)
        ud.set(config.textColor.rawValue,          forKey: StyleKey.textColor)
        ud.set(config.backgroundOpacity,           forKey: StyleKey.bgOpacity)
        ud.set(config.textAlignment.rawValue,      forKey: StyleKey.alignment)
        // Only persist the script when it differs from the default placeholder
        // so a fresh install still shows the onboarding hint text.
        if config.text != TeleprompterConfig.default.text {
            ud.set(config.text, forKey: StyleKey.scriptText)
        }
    }

    private func loadStylePreferences() {
        let ud = UserDefaults.standard
        // Only override defaults if a value has actually been saved previously.
        if ud.object(forKey: StyleKey.fontSize) != nil {
            config.fontSize            = ud.double(forKey: StyleKey.fontSize)
            config.speedPointsPerSecond = ud.double(forKey: StyleKey.speed)
            config.backgroundOpacity   = ud.double(forKey: StyleKey.bgOpacity)
            if let raw = ud.string(forKey: StyleKey.textColor),
               let color = TeleprompterTextColor(rawValue: raw) {
                config.textColor = color
            }
            if let raw = ud.string(forKey: StyleKey.alignment),
               let alignment = TeleprompterTextAlignment(rawValue: raw) {
                config.textAlignment = alignment
            }
            config = config.clamped
            // Restore the saved script. If no script has been saved yet (fresh
            // install or user cleared it), fall back to the default hint text.
            if let saved = ud.string(forKey: StyleKey.scriptText), !saved.isEmpty {
                config.text = saved
            } else {
                config.text = TeleprompterConfig.default.text
            }
            Log.viewmodel.debug("loadStylePreferences restored fontSize=\(Int(self.config.fontSize), privacy: .public) speed=\(Int(self.config.speedPointsPerSecond), privacy: .public) color=\(self.config.textColor.rawValue, privacy: .public) bgOpacity=\(self.config.backgroundOpacity, privacy: .public) scriptLen=\(self.config.text.count, privacy: .public)")
        }
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
                self.refreshLatestRecording()
            }
        }

        // Fires the instant PhotoKit actually persists the new asset — closes
        // the race where onRecordingStateChanged fires before the save is done.
        cameraService.onRecordingSavedToLibrary = { [weak self] in
            self?.refreshLatestRecording()
        }

        cameraService.onSessionRunningStateChanged = { [weak self] isRunning in
            guard let self else { return }
            self.isCameraReady = isRunning
            // Attach audio metering once the session is fully configured
            // and running. Attaching earlier fails because the session
            // hasn't added its audio input yet. `setup()` is idempotent.
            if isRunning {
                self.audioMeter.setup()
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
