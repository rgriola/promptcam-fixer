import AVFoundation
import Photos

struct PermissionService {
    // MARK: - Status Getters (no prompt triggered)

    var cameraStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var photoLibraryStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Returns `true` only when camera, mic, and photo library are all authorized.
    var allPermissionsGranted: Bool {
        cameraStatus == .authorized
            && microphoneStatus == .authorized
            && (photoLibraryStatus == .authorized || photoLibraryStatus == .limited)
    }

    /// Returns `true` when camera and microphone are both authorized.
    var cameraAndMicGranted: Bool {
        cameraStatus == .authorized && microphoneStatus == .authorized
    }

    // MARK: - Individual Request Methods

    func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func requestPhotoLibraryAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status == .authorized || status == .limited)
            }
        }
    }

    // MARK: - Aggregate Request (legacy convenience)

    func requestCameraAndMicrophoneAccess() async -> Bool {
        let cameraAuthorized = await requestCameraAccess()
        let microphoneAuthorized = await requestMicrophoneAccess()
        return cameraAuthorized && microphoneAuthorized
    }

    func requestPhotoLibraryAddAccess() async -> Bool {
        await requestPhotoLibraryAccess()
    }
}
