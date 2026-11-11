// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add TeleprompterTextColor presets and style fields
// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add TeleprompterTextAlignment enum
import Foundation
import SwiftUI

/// Text alignment options for the teleprompter overlay.
enum TeleprompterTextAlignment: String, CaseIterable, Equatable, Sendable {
    case center
    case left
    case right

    var swiftUIAlignment: TextAlignment {
        switch self {
        case .center: .center
        case .left: .leading
        case .right: .trailing
        }
    }

    var iconName: String {
        switch self {
        case .center: "text.aligncenter"
        case .left: "text.alignleft"
        case .right: "text.alignright"
        }
    }

    /// Returns the next alignment in the cycle: center → left → right → center
    var next: TeleprompterTextAlignment {
        switch self {
        case .center: .left
        case .left: .right
        case .right: .center
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
        case .white: Theme.white
        case .yellow: Theme.yellow
        case .red: Theme.red
        case .blue: Theme.blue
        case .black: Theme.black
        }
    }

    var label: String {
        rawValue.capitalized
    }
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
    /// Uppercases the script on screen only; `text` keeps the author's casing.
    var usesAllCaps: Bool = false

    /// Script as it should appear in the overlay. Render and measure with this, never `text`.
    var displayText: String {
        usesAllCaps ? text.uppercased() : text
    }

    static let `default` = TeleprompterConfig(
        text: "Tap script button below to load your script.",
        speedPointsPerSecond: 35,
        fontSize: 30,
        textColor: .white,
        backgroundOpacity: 0.15,
        textAlignment: .center,
        usesAllCaps: false,
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
