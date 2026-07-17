import AVFoundation
import Foundation

// MARK: - Video Mode

enum VideoMode: String, CaseIterable, Codable, Sendable {
    case standard = "Standard"
    case cinematic = "Cinematic"
    
    /// Display label for UI.
    var displayLabel: String { rawValue }
}

// MARK: - Video Resolution

enum VideoResolution: String, CaseIterable, Codable, Sendable {
    case hd1080p = "HD"
    case uhd4K = "4K"

    /// Full pixel dimension label for display, e.g. "1920×1080".
    var dimensionLabel: String {
        switch self {
        case .hd1080p: return "1920×1080"
        case .uhd4K:   return "3840×2160"
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd1080p: return .hd1920x1080
        case .uhd4K:   return .hd4K3840x2160
        }
    }
}

// MARK: - Video Frame Rate

enum VideoFrameRate: Int, CaseIterable, Codable, Sendable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var displayLabel: String { "\(rawValue)" }
}

// MARK: - Recording Format

struct RecordingFormat: Equatable, Hashable, Codable, Sendable {
    var resolution: VideoResolution
    var frameRate: VideoFrameRate
    var mode: VideoMode

    static let `default` = RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .standard)
}
