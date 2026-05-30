// May 29, 2026 - 11:23pm - GitHub Copilot
import AVFoundation
import SwiftUI

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var config = TeleprompterConfig.default
    @Published var isRecording = false
    @Published var isScrolling = false
    @Published var showPermissionsAlert = false
    @Published var errorMessage: String?

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
        cameraService.lockFocusExposure(at: devicePoint)
    }

    func unlockFocusExposure() {
        cameraService.unlockFocusExposure()
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
