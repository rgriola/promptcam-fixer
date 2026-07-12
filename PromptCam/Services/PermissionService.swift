import AVFoundation
import CoreLocation
import Photos
import Speech
import SwiftUI

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

/// View-facing state reducer for the required-access gate UI.
/// Keeps gate logic centralized and unit-testable.
struct RequiredAccessGateState: Equatable, Sendable {
    let snapshot: PermissionPolicySnapshot

    /// Continue button state — only required permissions gate entry.
    var canContinue: Bool {
        snapshot.requiredPermissionsGranted
    }

    /// Show warning copy when a required permission is blocked.
    var hasBlockedRequiredPermission: Bool {
        let cameraBlocked = snapshot.camera == .denied || snapshot.camera == .restricted
        let micBlocked = snapshot.microphone == .denied || snapshot.microphone == .restricted
        let photoBlocked = snapshot.photoLibrary == .denied || snapshot.photoLibrary == .restricted
        return cameraBlocked || micBlocked || photoBlocked
    }

    /// Controls visibility of the grant-permissions CTA.
    /// Includes optional permissions so users can opt in early.
    var hasUndeterminedPermission: Bool {
        snapshot.camera == .notDetermined
            || snapshot.microphone == .notDetermined
            || snapshot.photoLibrary == .notDetermined
            || snapshot.location == .notDetermined
            || snapshot.speechToText == .notDetermined
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

    /// Requests speech recognition access for optional transcription features.
    func requestSpeechToTextAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Requests "when in use" location access for video geo-tagging.
    /// CoreLocation has no async authorization API — the system dialog is shown
    /// and the status is refreshed when the scene becomes active again.
    ///
    /// Prefer `requestLocationAccessAsync()` in flows that chain multiple
    /// system prompts; the async variant waits for the user to dismiss the
    /// dialog so subsequent prompts do not overlap.
    func requestLocationAccess() {
        CLLocationManager().requestWhenInUseAuthorization()
    }

    /// Awaitable version of `requestLocationAccess()`.
    ///
    /// `CLLocationManager` does not expose an async authorization API, so this
    /// wraps the delegate callback in a `CheckedContinuation`. The call
    /// returns as soon as the user grants or denies access (or immediately
    /// if the status is already determined). This prevents the location
    /// dialog from stacking on top of other permission prompts in the
    /// onboarding flow.
    @discardableResult
    func requestLocationAccessAsync() async -> CLAuthorizationStatus {
        let requester = LocationAuthorizationRequester()
        return await requester.request()
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

// MARK: - Environment Injection

/// Environment key that vends a shared `PermissionService` to any view that
/// reads `@Environment(\.permissionService)`. Views should prefer this over
/// creating their own `PermissionService()` instance so a single source of
/// truth (and any future mock) can be swapped from the app root.
private struct PermissionServiceKey: EnvironmentKey {
    static let defaultValue = PermissionService()
}

extension EnvironmentValues {
    var permissionService: PermissionService {
        get { self[PermissionServiceKey.self] }
        set { self[PermissionServiceKey.self] = newValue }
    }
}

// MARK: - Location Authorization Requester

/// Bridges `CLLocationManager`'s delegate-based authorization prompt into an
/// awaitable async call. Kept private to `PermissionService` — callers should
/// use `PermissionService.requestLocationAccessAsync()` instead.
///
/// The class must outlive the system dialog, so it holds a strong reference
/// to its `CLLocationManager` and to the continuation until the delegate
/// callback fires with a determined status. `CLLocationManager` invokes its
/// delegate on the main thread by default, which is where we consume the
/// result, so `@unchecked Sendable` is safe here.
private final class LocationAuthorizationRequester: NSObject, CLLocationManagerDelegate,
    @unchecked Sendable
{
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    /// Presents the location authorization dialog (if needed) and resumes
    /// once the user responds. Returns immediately with the current status
    /// when authorization is already determined.
    func request() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // The delegate fires once immediately after assignment with the
        // current (still `.notDetermined`) status. Ignore that pass and wait
        // for the user's response.
        guard status != .notDetermined else { return }
        let pending = continuation
        continuation = nil
        pending?.resume(returning: status)
    }
}
