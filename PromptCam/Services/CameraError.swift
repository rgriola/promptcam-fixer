import Foundation

/// Structured error type for all camera-related failures.
///
/// Replaces ad-hoc string-based error messages with typed cases
/// that can be matched, logged, and localized consistently.
enum CameraError: LocalizedError, Sendable {
    // Session / device
    case deviceUnavailable
    case inputConfigurationFailed
    case outputConfigurationFailed
    case sessionConfigurationFailed(String)
    case sessionNotReady
    /// Non-recoverable AVCaptureSession runtime error. Fired when
    /// `AVCaptureSession.runtimeErrorNotification` posts an error we can't
    /// automatically recover from (i.e. not `.mediaServicesWereReset`).
    case sessionRuntimeError(String)

    // Format
    case formatChangeDuringRecording
    case formatUnavailable(String)
    case frameRateFailed(String)

    /// Recording
    case recordingFailed(String)

    /// Focus / exposure
    case focusExposureFailed(String)

    // Photo library
    case photoLibraryPermissionDenied
    case photoLibrarySaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            "No camera device found."
        case .inputConfigurationFailed:
            "Failed to prepare camera inputs/outputs."
        case .outputConfigurationFailed:
            "Failed to add movie output."
        case let .sessionConfigurationFailed(detail):
            "Failed to configure camera: \(detail)"
        case .sessionNotReady:
            "Camera is still preparing. Try again in a moment."
        case let .sessionRuntimeError(detail):
            "Camera stopped unexpectedly: \(detail)"
        case .formatChangeDuringRecording:
            "Cannot change format while recording."
        case let .formatUnavailable(detail):
            "Format unavailable: \(detail)"
        case let .frameRateFailed(detail):
            "Failed to set frame rate: \(detail)"
        case let .recordingFailed(detail):
            "Recording failed: \(detail)"
        case let .focusExposureFailed(detail):
            "Focus/exposure error: \(detail)"
        case .photoLibraryPermissionDenied:
            "Photo library permission is required to save recordings. Please grant access in Settings."
        case let .photoLibrarySaveFailed(detail):
            "Failed to save video: \(detail)"
        }
    }
}
