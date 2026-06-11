// May 31, 2026 - 2:30am - GitHub Copilot (Claude Opus 4.7)
import AVFoundation
import SwiftUI

enum CameraSheetRoute: String, Identifiable {
    case formatPanel
    case composeScript
    case settings

    var id: String { rawValue }
}

enum CameraMode: Equatable {
    case camera
    case compose
}

enum CameraLockStatus: Equatable {
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

    var errorMessage: String?
    var lockStatus: CameraLockStatus = .auto
    var isCameraReady = false
    var isPhotoPickerPresented = false
    var activeSheet: CameraSheetRoute?
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

    // MARK: - Modal Queue State
    // See class-level doc for explanation of the queue pattern.

    @ObservationIgnored private var queuedSheet: CameraSheetRoute?
    @ObservationIgnored private var queuedPhotoPicker = false
    @ObservationIgnored private var lastPresentedSheet: CameraSheetRoute?

    // MARK: - Style Persistence Keys
    private enum StyleKey {
        static let fontSize   = "tp.fontSize"
        static let speed      = "tp.speed"
        static let textColor  = "tp.textColor"
        static let bgOpacity  = "tp.bgOpacity"
    }

    let cameraService: CameraService
    private let permissionService: PermissionService

    init(
        cameraService: CameraService = CameraService(),
        permissionService: PermissionService = PermissionService()
    ) {
        self.cameraService = cameraService
        self.permissionService = permissionService
        self.recordingFormat = RecordingFormat.loadSaved()
        loadStylePreferences()
        bindCallbacks()
    }

    var session: AVCaptureSession { cameraService.session }

    func onAppear() {
        isCameraReady = false
        // Permissions are already granted by the onboarding page.
        cameraService.configureSession(format: recordingFormat)
        cameraService.startSession()
        // Supported formats are received via onSupportedFormatsQueried callback
        // after configureSession completes on the session queue.
    }

    func onDisappear() {
        cameraService.stopSession()
        isCameraReady = false
    }

    func toggleRecording() {
        guard isCameraReady else { return }

        if isRecording {
            cameraService.stopRecording()
            print("[r] VM toggleRecording -> stopped")
        } else {
            cameraService.startRecording()
            print("[r] VM toggleRecording -> started")
        }
    }

    func toggleScrolling() {
        isScrolling.toggle()
        print("[tScroll] VM toggleScrolling -> \(isScrolling)")
    }

    func openPhotoLibrary() {
        // Only one modal presenter can be active at a time in SwiftUI.
        guard !isPhotoPickerPresented else { return }

        if activeSheet != nil {
            queuedPhotoPicker = true
            dismissActiveSheet()
            return
        }

        isPhotoPickerPresented = true
    }

    

    func openCompose() {
        presentSheet(.composeScript)
    }

    func openSettings() {
        presentSheet(.settings)
    }



    func openFormatPanel() {
        // Gate: Cannot change format while recording
        guard !isRecording else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showFormatLockedWarning = true
            }
            return
        }// Sheet to change format
        presentSheet(.formatPanel)
    }

    func openEVSlider (){
        
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

    func handlePhotoPickerStateChanged(_ newValue: Bool) {
        guard !newValue else { return }

        presentQueuedModalIfNeeded()
    }

    func updateScriptText(_ text: String) {
        print("[uScriptText] VM updateScriptText len=\(text.count)")
        config.text = text
    }

    /// Applies and clamps new style settings, then persists them.
    func updateTeleprompterStyle(_ updated: TeleprompterConfig) {
        // Preserve the current script text — only style fields change here.
        var next = updated.clamped
        next.text = config.text
        config = next
        saveStylePreferences()
        print("[TP] updateTeleprompterStyle fontSize=\(Int(config.fontSize)) speed=\(Int(config.speedPointsPerSecond)) color=\(config.textColor.rawValue) bgOpacity=\(config.backgroundOpacity)")
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
            print("[TP] loadStylePreferences restored fontSize=\(Int(config.fontSize)) speed=\(Int(config.speedPointsPerSecond)) color=\(config.textColor.rawValue) bgOpacity=\(config.backgroundOpacity)")
        }
    }

    /// Resets the teleprompter to its centered starting position.
    /// Pauses scrolling first so the reset is visible to the user.
    func resetTeleprompterPosition() {
        if isScrolling {
            isScrolling = false
            print("[rTP] VM resetTeleprompterPosition paused scrolling")
        }
        teleprompterResetToken += 1
        print("[TP] VM resetTeleprompterPosition token=\(teleprompterResetToken)")
    }

    private func presentSheet(_ route: CameraSheetRoute) {
        if isPhotoPickerPresented {
            queuedSheet = route
            isPhotoPickerPresented = false
            return
        }

        guard activeSheet == nil else {
            queuedSheet = route
            return
        }

        if route == .composeScript {
            cameraMode = .compose
        }

        lastPresentedSheet = route
        activeSheet = route
    }

    private func presentQueuedModalIfNeeded() {
        guard activeSheet == nil else { return }

        if queuedPhotoPicker {
            queuedPhotoPicker = false
            isPhotoPickerPresented = true
            return
        }

        if let route = queuedSheet {
            queuedSheet = nil
            presentSheet(route)
        }
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
        print("[TP] VM updateRecordingFormat res=\(format.resolution.rawValue) fps=\(format.frameRate.rawValue)")
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
            print("[TP] VM format applied res=\(applied.resolution.rawValue) fps=\(applied.frameRate.rawValue)")
        }

        cameraService.onSupportedFormatsQueried = { [weak self] resolutions, frameRates in
            guard let self else { return }
            self.supportedResolutions = resolutions
            self.supportedFrameRates = frameRates
            print("[TP] VM supported formats res=\(resolutions.map(\.rawValue)) fps=\(frameRates.map(\.rawValue))")

            // If saved format isn't supported by this hardware, fall back.
            if !resolutions.contains(self.recordingFormat.resolution) ||
               !frameRates.contains(self.recordingFormat.frameRate) {
                let fallback = RecordingFormat(
                    resolution: resolutions.first ?? .hd1080p,
                    frameRate: frameRates.contains(.fps30) ? .fps30 : (frameRates.first ?? .fps30)
                )
                self.recordingFormat = fallback
                fallback.save()
                print("[TP] VM format fell back to res=\(fallback.resolution.rawValue) fps=\(fallback.frameRate.rawValue)")
            }
        }

        cameraService.onError = { [weak self] message in
            self?.errorMessage = message
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
