// May 29, 2026 - 11:23pm - GitHub Copilot
import AVFoundation
import SwiftUI

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
        Task {
            let cameraAndMicAuthorized = await permissionService.requestCameraAndMicrophoneAccess()
            let photoAuthorized = await permissionService.requestPhotoLibraryAddAccess()

            guard cameraAndMicAuthorized && photoAuthorized else {
                showPermissionsAlert = true
                return
            }

            cameraService.configureSession()
            cameraService.startSession()
        }
    }

    func onDisappear() {
        cameraService.stopSession()
    }

    func toggleRecording() {
        if isRecording {
            cameraService.stopRecording()
        } else {
            cameraService.startRecording()
        }
    }

    func toggleScrolling() {
        isScrolling.toggle()
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
