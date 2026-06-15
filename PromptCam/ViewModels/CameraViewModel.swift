// May 31, 2026 - 2:30am - GitHub Copilot (Claude Opus 4.7)
// June 13, 2026 - GitHub Copilot (Claude Sonnet 4.5) - Added recording timer with Combine
import AVFoundation
import Combine
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
}

/// Central state owner for the camera screen.
///
/// **@MainActor**: All published properties drive SwiftUI views, so the entire
/// class is main-actor-isolated. Camera hardware calls go through `CameraService`
/// which runs them on its own serial queue.
///
/// **Modal queue pattern**: SwiftUI allows only one `.sheet` presenter at a time.
/// If the user triggers a second modal while one is active, the request is queued
/// in `queuedSheet` (or `queuedPhotoPicker`). When the active modal dismisses,
/// `presentQueuedModalIfNeeded()` dequeues the next one. This prevents the
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
    /// Recording duration in seconds, updated every 0.1s while recording.
    var recordingDuration: TimeInterval = 0

    var cameraError: CameraError?
    var lockStatus: CameraLockStatus = .auto
    var isCameraReady = false
    var activeSheet: CameraSheetRoute?
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
    /// Hardware-supported resolutions for the active camera.
    var supportedResolutions: [VideoResolution] = VideoResolution.allCases
    /// Hardware-supported frame rates for the active camera.
    var supportedFrameRates: [VideoFrameRate] = VideoFrameRate.allCases
    /// Device capabilities (mode support, resolution/fps per mode).
    var deviceCapabilities: DeviceCapabilities = DeviceCapabilities(
        supportsCinematicMode: false,
        standardResolutions: [.hd1080p],
        standardFrameRates: [.fps30],
        cinematicResolutions: [],
        cinematicFrameRates: []
    )
    /// Aperture range reported by the active cinematic format (iOS 26+ only).
    /// Nil when cinematic mode is inactive or device/OS does not support it.
    var cinematicApertureRange: ClosedRange<Float>? = nil
    /// Current simulated aperture value shown in the aperture slider.
    var cinematicSimulatedAperture: Float = 2.0

    // MARK: - Timer State
    
    @ObservationIgnored private var timerCancellable: AnyCancellable?
    @ObservationIgnored private var recordingStartDate: Date?
    
    // MARK: - Modal Queue State
    // See class-level doc for explanation of the queue pattern.

    @ObservationIgnored private var queuedSheet: CameraSheetRoute?
    @ObservationIgnored private var lastPresentedSheet: CameraSheetRoute?

    // MARK: - Style Persistence Keys
    private enum StyleKey {
        static let fontSize   = "tp.fontSize"
        static let speed      = "tp.speed"
        static let textColor  = "tp.textColor"
        static let bgOpacity  = "tp.bgOpacity"
    }

    let cameraService: CameraServiceProtocol
    private let permissionService: PermissionService

    /// Shared with RecordingsLibrarySheet — pre-fetched on appear so the
    /// Camera Roll opens instantly.
    let recordingsLibraryViewModel = RecordingsLibraryViewModel()

    init(
        cameraService: CameraServiceProtocol = CameraService(),
        permissionService: PermissionService = PermissionService()
    ) {
        self.cameraService = cameraService
        self.permissionService = permissionService
        self.recordingFormat = RecordingFormat.loadSaved()
        loadStylePreferences()
        bindCallbacks()
    }

    var session: AVCaptureSession { cameraService.previewSession }

    func onAppear() {
        isCameraReady = false
        // Permissions are already granted by the onboarding page.
        cameraService.configureSession(format: recordingFormat)
        cameraService.startSession()
        // Supported formats are received via onSupportedFormatsQueried callback
        // after configureSession completes on the session queue.

        // Pre-fetch recordings list + first page of thumbnails in the background
        // so the Camera Roll sheet opens instantly.
        Task { await recordingsLibraryViewModel.prefetch() }
    }

    func onDisappear() {
        stopTimer()
        cameraService.stopSession()
        isCameraReady = false
    }

    func toggleRecording() {
        guard isCameraReady else { return }

        if isRecording {
            stopTimer()
            cameraService.stopRecording()
            Log.viewmodel.info("toggleRecording -> stopped")
        } else {
            startTimer()
            cameraService.startRecording()
            Log.viewmodel.info("toggleRecording -> started")
        }
    }

    func toggleScrolling() {
        isScrolling.toggle()
        Log.viewmodel.debug("toggleScrolling -> \(self.isScrolling, privacy: .public)")
    }

    func openPhotoLibrary() {
        presentSheet(.recordingsLibrary)
    }

    

    func openCompose() {
        cameraMode = .compose
        showComposeSheet = true
    }

    func dismissComposeSheet() {
        showComposeSheet = false
        cameraMode = .camera
    }

    func openSettings() {
        presentSheet(.settings)
    }



    func openFormatPanel() {
        // Gate: Cannot change format while recording
        guard !isRecording else {
            withAnimation(Theme.panelSpring) {
                showFormatLockedWarning = true
            }
            return
        }// Sheet to change format
        presentSheet(.formatPanel)
    }



    func dismissActiveSheet() {
        activeSheet = nil
    }

    func handleSheetStateChanged(_ newValue: CameraSheetRoute?) {
        guard newValue == nil else { return }

        if lastPresentedSheet == .composeScript {
            cameraMode = .camera
        }

        lastPresentedSheet = nil
        presentQueuedModalIfNeeded()
    }



    func updateScriptText(_ text: String) {
        Log.viewmodel.debug("updateScriptText len=\(text.count, privacy: .public)")
        config.text = text
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

    // MARK: - Style Persistence

    private func saveStylePreferences() {
        let ud = UserDefaults.standard
        ud.set(config.fontSize,                   forKey: StyleKey.fontSize)
        ud.set(config.speedPointsPerSecond,        forKey: StyleKey.speed)
        ud.set(config.textColor.rawValue,          forKey: StyleKey.textColor)
        ud.set(config.backgroundOpacity,           forKey: StyleKey.bgOpacity)
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
            config = config.clamped
            config.text = TeleprompterConfig.default.text
            Log.viewmodel.debug("loadStylePreferences restored fontSize=\(Int(self.config.fontSize), privacy: .public) speed=\(Int(self.config.speedPointsPerSecond), privacy: .public) color=\(self.config.textColor.rawValue, privacy: .public) bgOpacity=\(self.config.backgroundOpacity, privacy: .public)")
        }
    }

    /// Resets the teleprompter to its centered starting position.
    /// Pauses scrolling first so the reset is visible to the user.
    func resetTeleprompterPosition() {
        if isScrolling {
            isScrolling = false
            Log.viewmodel.debug("resetTeleprompterPosition paused scrolling")
        }
        teleprompterResetToken += 1
        Log.viewmodel.debug("resetTeleprompterPosition token=\(self.teleprompterResetToken, privacy: .public)")
    }

    private func presentSheet(_ route: CameraSheetRoute) {
        guard activeSheet == nil else {
            queuedSheet = route
            return
        }

        // .composeScript is routed through showComposeSheet / fullScreenCover
        // to prevent the camera preview from being rescaled.

        lastPresentedSheet = route
        activeSheet = route
    }

    private func presentQueuedModalIfNeeded() {
        guard activeSheet == nil, let route = queuedSheet else { return }
        queuedSheet = nil
        presentSheet(route)
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
    
    // MARK: - Recording Timer
    
    /// Starts the recording timer using Combine. Computes duration from a start
    /// date rather than accumulating increments, avoiding floating-point drift.
    private func startTimer() {
        recordingDuration = 0
        recordingStartDate = Date()
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.recordingStartDate else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        Log.viewmodel.debug("Recording timer started")
    }
    
    /// Stops and resets the recording timer.
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        recordingStartDate = nil
        recordingDuration = 0
        Log.viewmodel.debug("Recording timer stopped")
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
            self?.isRecording = isRecording
        }

        cameraService.onSessionRunningStateChanged = { [weak self] isRunning in
            self?.isCameraReady = isRunning
        }

        cameraService.onFormatApplied = { [weak self] applied in
            guard let self else { return }
            self.recordingFormat = applied
            applied.save()
            Log.viewmodel.info("format applied res=\(applied.resolution.rawValue, privacy: .public) fps=\(applied.frameRate.rawValue, privacy: .public)")
        }

        cameraService.onSupportedFormatsQueried = { [weak self] resolutions, frameRates in
            guard let self else { return }
            self.supportedResolutions = resolutions
            self.supportedFrameRates = frameRates
            Log.viewmodel.debug("supported formats res=\(resolutions.map(\.rawValue), privacy: .public) fps=\(frameRates.map(\.rawValue), privacy: .public)")

            // If saved format isn't supported by this hardware, fall back.
            if !resolutions.contains(self.recordingFormat.resolution) ||
               !frameRates.contains(self.recordingFormat.frameRate) {
                let fallback = RecordingFormat(
                    resolution: resolutions.first ?? .hd1080p,
                    frameRate: frameRates.contains(.fps30) ? .fps30 : (frameRates.first ?? .fps30),
                    mode: .standard
                )
                self.recordingFormat = fallback
                fallback.save()
                Log.viewmodel.notice("format fell back to res=\(fallback.resolution.rawValue, privacy: .public) fps=\(fallback.frameRate.rawValue, privacy: .public)")
            }
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
                self.cinematicApertureRange = minAp...maxAp
                self.cinematicSimulatedAperture = defAp
                Log.viewmodel.info("Cinematic aperture range f/\(minAp, privacy: .public)–f/\(maxAp, privacy: .public) default f/\(defAp, privacy: .public)")
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
