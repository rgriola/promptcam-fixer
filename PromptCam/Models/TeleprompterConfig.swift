// May 31, 2026 - 12:45am - GitHub Copilot (Claude Opus 4.7)
import Foundation

struct TeleprompterConfig: Equatable {
    var text: String
    var speedPointsPerSecond: Double
    var fontSize: Double
    /// Normalized scroll position. Matches the slider lane: knob TOP = 1, knob BOTTOM = 0.
    /// 1 = first line sits at viewport bottom (start of read); 0 = last line sits at viewport top (fully scrolled); 0.5 = centered.
    var startOffsetProgress: Double = 1.0

    static let `default` = TeleprompterConfig(
        text: "Paste or type your script here.",
        speedPointsPerSecond: 35,
        fontSize: 30
    )

    var clamped: TeleprompterConfig {
        var copy = self
        copy.speedPointsPerSecond = min(max(speedPointsPerSecond, 5), 150)
        let clampedFont = min(max(fontSize, 16), 72)
        copy.fontSize = round(clampedFont / 2) * 2 // snap to even pt sizes
        copy.startOffsetProgress = min(max(startOffsetProgress, 0), 1)
        return copy
    }
}
