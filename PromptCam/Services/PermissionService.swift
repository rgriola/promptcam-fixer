import AVFoundation
import CoreLocation
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

    /// Current location authorization status (read-only, no prompt).
    var locationStatus: CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
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
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Requests "when in use" location access for video geo-tagging.
    /// CoreLocation has no async authorization API — the system dialog is shown
    /// and the status is refreshed when the scene becomes active again.
    func requestLocationAccess() {
        CLLocationManager().requestWhenInUseAuthorization()
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
