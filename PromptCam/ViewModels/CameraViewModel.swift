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

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var config = TeleprompterConfig.default
    @Published var isRecording = false
    @Published var isScrolling = false
    @Published var showPermissionsAlert = false
    @Published var errorMessage: String?
    @Published var lockStatus: CameraLockStatus = .auto
    @Published var isCameraReady = false
    @Published var isPhotoPickerPresented = false
    @Published var activeSheet: CameraSheetRoute?
    @Published var cameraMode: CameraMode = .camera
    /// Bumped to signal the overlay to reset position (zero manualOffset).
    @Published var teleprompterResetToken: Int = 0
    /// Current recording format (resolution + FPS). Persisted across launches.
    @Published var recordingFormat: RecordingFormat
    /// Hardware-supported resolutions for the active camera.
    @Published var supportedResolutions: [VideoResolution] = VideoResolution.allCases
    /// Hardware-supported frame rates for the active camera.
    @Published var supportedFrameRates: [VideoFrameRate] = VideoFrameRate.allCases

    private var queuedSheet: CameraSheetRoute?
    private var queuedPhotoPicker = false
    private var lastPresentedSheet: CameraSheetRoute?

    let cameraService: CameraService
    private let permissionService: PermissionService

    init(
        cameraService: CameraService = CameraService(),
        permissionService: PermissionService = PermissionService()
    ) {
        self.cameraService = cameraService
        self.permissionService = permissionService
        self.recordingFormat = RecordingFormat.loadSaved()

        bindCallbacks()
    }

    var session: AVCaptureSession { cameraService.session }

    func onAppear() {
        isCameraReady = false

        Task {
            let cameraAndMicAuthorized = await permissionService.requestCameraAndMicrophoneAccess()
            guard cameraAndMicAuthorized else {
                showPermissionsAlert = true
                return
            }

            cameraService.configureSession(format: recordingFormat)
            cameraService.startSession()

            // Query hardware capabilities after session is configured.
            let supported = cameraService.supportedFormats()
            supportedResolutions = supported.resolutions
            supportedFrameRates = supported.frameRates

            // If saved format isn't supported, fall back to default.
            if !supportedResolutions.contains(recordingFormat.resolution) ||
               !supportedFrameRates.contains(recordingFormat.frameRate) {
                let fallback = RecordingFormat(
                    resolution: supportedResolutions.first ?? .hd1080p,
                    frameRate: supportedFrameRates.contains(.fps30) ? .fps30 : (supportedFrameRates.first ?? .fps30)
                )
                recordingFormat = fallback
                fallback.save()
            }
        }
    }

    func onDisappear() {
        cameraService.stopSession()
        isCameraReady = false
    }

    func toggleRecording() {
        guard isCameraReady else { return }

        if isRecording {
            cameraService.stopRecording()
        } else {
            cameraService.startRecording()
        }
    }

    func toggleScrolling() {
        isScrolling.toggle()
        print("[TP] VM toggleScrolling -> \(isScrolling)")
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

    func handlePhotoPickerStateChanged(_ newValue: Bool) {
        guard !newValue else { return }

        presentQueuedModalIfNeeded()
    }

    func updateScriptText(_ text: String) {
        print("[TP] VM updateScriptText len=\(text.count)")
        config.text = text
    }

    /// Resets the teleprompter to its centered starting position.
    /// Pauses scrolling first so the reset is visible to the user.
    func resetTeleprompterPosition() {
        if isScrolling {
            isScrolling = false
            print("[TP] VM resetTeleprompterPosition paused scrolling")
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
