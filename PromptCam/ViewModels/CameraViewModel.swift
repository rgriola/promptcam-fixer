// May 30, 2026 - 9:29pm - GitHub Copilot
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

            cameraService.configureSession()
            cameraService.startSession()
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
        config.text = text
    }

    func updateScriptStartProgress(_ progress: Double) {
        config.startOffsetProgress = progress
        config = config.clamped
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

    private func bindCallbacks() {
        cameraService.onRecordingStateChanged = { [weak self] isRecording in
            self?.isRecording = isRecording
        }

        cameraService.onSessionRunningStateChanged = { [weak self] isRunning in
            self?.isCameraReady = isRunning
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
