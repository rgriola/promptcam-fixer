import AVFoundation
import CoreLocation
import Photos
import Speech

/// Snapshot of permission states used to evaluate required-vs-optional policy.
struct PermissionPolicySnapshot: Equatable, Sendable {
    let camera: AVAuthorizationStatus
    let microphone: AVAuthorizationStatus
    let photoLibrary: PHAuthorizationStatus
    let location: CLAuthorizationStatus
    let speechToText: SFSpeechRecognizerAuthorizationStatus

    /// Required permissions for core recording flow.
    var requiredPermissionsGranted: Bool {
        camera == .authorized
            && microphone == .authorized
            && (photoLibrary == .authorized || photoLibrary == .limited)
    }

    /// Optional permissions should never gate camera entry.
    var optionalPermissionsGranted: Bool {
        let locationGranted = location == .authorizedWhenInUse || location == .authorizedAlways
        let speechGranted = speechToText == .authorized
        return locationGranted && speechGranted
    }

    /// App entry should be blocked only by missing required permissions.
    var shouldBlockAppEntry: Bool {
        !requiredPermissionsGranted
    }

    /// Speech-to-Text is optional and only impacts transcription surfaces.
    var isSpeechToTextAvailable: Bool {
        speechToText == .authorized
    }
}

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

    /// Current speech recognition authorization status (read-only, no prompt).
    var speechToTextStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// Live policy snapshot for app routing decisions.
    var policySnapshot: PermissionPolicySnapshot {
        PermissionPolicySnapshot(
            camera: cameraStatus,
            microphone: microphoneStatus,
            photoLibrary: photoLibraryStatus,
            location: locationStatus,
            speechToText: speechToTextStatus
        )
    }

    /// Returns `true` only when camera, mic, and photo library are all authorized.
    var allPermissionsGranted: Bool {
        policySnapshot.requiredPermissionsGranted
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
