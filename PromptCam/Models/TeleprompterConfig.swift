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
        TeleprompterConfig(
            text: text,
            speedPointsPerSecond: min(max(speedPointsPerSecond, 5), 150),
            fontSize: min(max(fontSize, 16), 72)
        )
    }
}
