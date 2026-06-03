import Foundation

struct TeleprompterConfig: Equatable {
    var text: String
    var speedPointsPerSecond: Double
    var fontSize: Double

    static let `default` = TeleprompterConfig(
        text: "Middle Bottom Button Opens The Compose Screen To Type or Past Your Script.",
        speedPointsPerSecond: 35,
        fontSize: 30
    )

    var clamped: TeleprompterConfig {
        var copy = self
        copy.speedPointsPerSecond = min(max(speedPointsPerSecond, 5), 150)
        let clampedFont = min(max(fontSize, 16), 72)
        copy.fontSize = round(clampedFont / 2) * 2 // snap to even pt sizes
        return copy
    }
}
