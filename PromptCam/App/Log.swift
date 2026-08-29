import os
import Foundation

/// Centralized OSLog loggers. Prefer `Log.{category}.debug(...)` over `print()`
/// so traces are stripped from Release builds and filterable in Console.app.
enum Log {
    private static let subsystem = "com.promptcam.fixer"
    private static let sessionStartUptime = ProcessInfo.processInfo.systemUptime

    static let camera = Logger(subsystem: subsystem, category: "Camera")
    /// Audio capture/metering diagnostics. Filter Console.app on this category
    /// alone to correlate the VU meter against what the recording actually got.
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let viewmodel = Logger(subsystem: subsystem, category: "ViewModel")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let teleprompter = Logger(subsystem: subsystem, category: "Teleprompter")
    static let recordings = Logger(subsystem: subsystem, category: "Recordings")
    static let hdmi = Logger(subsystem: subsystem, category: "HDMI")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let analytics = Logger(subsystem: subsystem, category: "Analytics")

    /// Signposter for timing camera/audio restart intervals in Instruments
    /// (Points of Interest track). Shares the "Camera" category so signposts
    /// interleave with `Log.camera`'s log lines in Console.app.
    static let cameraSignposter = OSSignposter(logger: camera)

    /// Monotonic elapsed timestamp since app process launch.
    /// Example: "t+15234ms".
    static func ts() -> String {
        let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - sessionStartUptime) * 1000)
        return "t+\(elapsedMs)ms"
    }
}
