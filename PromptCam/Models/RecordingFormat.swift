import AVFoundation
import Foundation

// MARK: - Video Resolution

enum VideoResolution: String, CaseIterable, Codable {
    case hd1080p = "HD"
    case uhd4K = "4K"

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd1080p: return .hd1920x1080
        case .uhd4K:   return .hd4K3840x2160
        }
    }
}

// MARK: - Video Frame Rate

enum VideoFrameRate: Int, CaseIterable, Codable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var displayLabel: String { "\(rawValue)" }
}

// MARK: - Recording Format

struct RecordingFormat: Equatable, Codable {
    var resolution: VideoResolution
    var frameRate: VideoFrameRate

    static let `default` = RecordingFormat(resolution: .hd1080p, frameRate: .fps30)

    // MARK: - UserDefaults Persistence

    private static let storageKey = "com.promptcam.recordingFormat"

    /// Loads from UserDefaults, falling back to `.default` if nothing is saved or decoding fails.
    static func loadSaved() -> RecordingFormat {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let format = try? JSONDecoder().decode(RecordingFormat.self, from: data) else {
            return .default
        }
        return format
    }

    /// Persists the current format to UserDefaults.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
