// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add TeleprompterTextColor presets and style fields
// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add TeleprompterTextAlignment enum
import Foundation
import SwiftUI

/// Text alignment options for the teleprompter overlay.
enum TeleprompterTextAlignment: String, CaseIterable, Equatable, Sendable {
    case center
    case left
   // case right
    
    var swiftUIAlignment: TextAlignment {
        switch self {
        case .center: return .center
        case .left: return .leading
       // case .right: return .trailing
        }
    }
    
    var iconName: String {
        switch self {
        case .center: return "text.aligncenter"
        case .left: return "text.alignleft"
        //case .right: return "text.alignright"
        }
    }
    
    /// Returns the next alignment in the cycle: center → left → right → center
    var next: TeleprompterTextAlignment {
        switch self {
        case .center: return .left
        case .left: return .center
       // case .left: return .right
       // case .right: return .center
        }
    }
}

/// Preset text colors for the teleprompter overlay.
/// `rawValue` is a plain string so values can be round-tripped through UserDefaults without extra work.
enum TeleprompterTextColor: String, CaseIterable, Equatable, Sendable {
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

struct TeleprompterConfig: Equatable, Sendable {
    var text: String
    var speedPointsPerSecond: Double
    var fontSize: Double
    /// Preset color applied to the scrolling script text.
    var textColor: TeleprompterTextColor
    /// Opacity of the dark scrim behind the text. Range: 0.0–0.85.
    var backgroundOpacity: Double
    /// Text alignment for the teleprompter script.
    var textAlignment: TeleprompterTextAlignment

    static let `default` = TeleprompterConfig(
        text: "Tap script button below to load your script.",
        speedPointsPerSecond: 35,
        fontSize: 30,
        textColor: .white,
        backgroundOpacity: 0.15,
        textAlignment: .center
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
