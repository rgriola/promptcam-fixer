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

    // Format
    case formatChangeDuringRecording
    case formatUnavailable(String)
    case frameRateFailed(String)

    // Recording
    case recordingFailed(String)

    // Focus / exposure
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
        case .sessionConfigurationFailed(let detail):
            "Failed to configure camera: \(detail)"
        case .sessionNotReady:
            "Camera is still preparing. Try again in a moment."
        case .formatChangeDuringRecording:
            "Cannot change format while recording."
        case .formatUnavailable(let detail):
            "Format unavailable: \(detail)"
        case .frameRateFailed(let detail):
            "Failed to set frame rate: \(detail)"
        case .recordingFailed(let detail):
            "Recording failed: \(detail)"
        case .focusExposureFailed(let detail):
            "Focus/exposure error: \(detail)"
        case .photoLibraryPermissionDenied:
            "Photo library permission is required to save recordings. Please grant access in Settings."
        case .photoLibrarySaveFailed(let detail):
            "Failed to save video: \(detail)"
        }
    }
}
