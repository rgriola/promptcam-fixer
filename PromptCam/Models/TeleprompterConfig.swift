// May 29, 2026 - 12:57pm - GitHub Copilot
import Foundation

struct TeleprompterConfig: Equatable {
    var text: String
    var speedPointsPerSecond: Double
    var fontSize: Double

    static let `default` = TeleprompterConfig(
        text: "Paste or type your script here.",
        speedPointsPerSecond: 35,
        fontSize: 30
    )

    var clamped: TeleprompterConfig {
        let clampedSpeed = min(max(speedPointsPerSecond, 5), 150)
        let clampedFont = min(max(fontSize, 16), 72)
        let evenFont = round(clampedFont / 2) * 2

        return TeleprompterConfig(
            text: text,
            speedPointsPerSecond: clampedSpeed,
            fontSize: evenFont
        )
    }
}
