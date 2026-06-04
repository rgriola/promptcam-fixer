// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add TeleprompterTextColor presets and style fields
import Foundation
import SwiftUI

/// Preset text colors for the teleprompter overlay.
/// `rawValue` is a plain string so values can be round-tripped through UserDefaults without extra work.
enum TeleprompterTextColor: String, CaseIterable, Equatable {
    case white
    case yellow
    case red
    case blue
    case black

    var color: Color {
        switch self {
        case .white:  return Theme.white
        case .yellow: return Theme.yellow
        case .red:    return Theme.red
        case .blue:   return Theme.blue
        case .black:  return Theme.black
        }
    }

    var label: String { rawValue.capitalized }
}

struct TeleprompterConfig: Equatable {
    var text: String
    var speedPointsPerSecond: Double
    var fontSize: Double
    /// Preset color applied to the scrolling script text.
    var textColor: TeleprompterTextColor
    /// Opacity of the dark scrim behind the text. Range: 0.0–0.85.
    var backgroundOpacity: Double

    static let `default` = TeleprompterConfig(
        text: "Tap script button below to load your script.",
        speedPointsPerSecond: 35,
        fontSize: 30,
        textColor: .white,
        backgroundOpacity: 0.15
    )

    var clamped: TeleprompterConfig {
        var copy = self
        copy.speedPointsPerSecond = min(max(speedPointsPerSecond, 5), 150)
        let clampedFont = min(max(fontSize, 16), 72)
        copy.fontSize = round(clampedFont / 2) * 2 // snap to even pt sizes
        copy.backgroundOpacity = min(max(backgroundOpacity, 0.0), 0.85)
        return copy
    }
}
