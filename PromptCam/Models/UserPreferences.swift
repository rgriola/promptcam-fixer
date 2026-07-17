import Foundation

/// Single Codable struct holding all user preferences.
///
/// Consolidates the ~10 scattered UserDefaults keys that were previously spread
/// across `TeleprompterStyleStore` (6 keys), `RecordingFormat` (1 key), and
/// `@AppStorage` into one atomic JSON blob.
///
/// `ScriptArchive` is intentionally excluded — it is a rolling collection of up
/// to 10 entries with time-based pruning, not a simple preference.
struct UserPreferences: Codable, Equatable, Sendable {

    // MARK: - Teleprompter Style

    /// Font size for the teleprompter text (16–72 pt, snapped to even).
    var fontSize: Double
    /// Auto-scroll speed in points per second (5–150).
    var speedPointsPerSecond: Double
    /// Raw value of `TeleprompterTextColor` (e.g. "white", "yellow").
    var textColor: String
    /// Opacity of the dark scrim behind the script text (0.0–0.85).
    var backgroundOpacity: Double
    /// Raw value of `TeleprompterTextAlignment` (e.g. "center", "left").
    var textAlignment: String
    /// User's script text. `nil` means "show the default onboarding hint".
    var scriptText: String?

    // MARK: - Recording

    /// Persisted recording format (resolution + FPS + mode).
    var recordingFormat: RecordingFormat

    // MARK: - Defaults

    /// Factory defaults. The user can always restore these via the UI.
    static let `default` = UserPreferences(
        fontSize: TeleprompterConfig.default.fontSize,
        speedPointsPerSecond: TeleprompterConfig.default.speedPointsPerSecond,
        textColor: TeleprompterConfig.default.textColor.rawValue,
        backgroundOpacity: TeleprompterConfig.default.backgroundOpacity,
        textAlignment: TeleprompterConfig.default.textAlignment.rawValue,
        scriptText: nil,
        recordingFormat: .default
    )
}
