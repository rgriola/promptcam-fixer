import os

/// Centralized OSLog loggers. Prefer `Log.{category}.debug(...)` over `print()`
/// so traces are stripped from Release builds and filterable in Console.app.
enum Log {
    private static let subsystem = "com.promptcam.fixer"

    static let camera = Logger(subsystem: subsystem, category: "Camera")
    static let viewmodel = Logger(subsystem: subsystem, category: "ViewModel")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let teleprompter = Logger(subsystem: subsystem, category: "Teleprompter")
    static let recordings = Logger(subsystem: subsystem, category: "Recordings")
    static let hdmi = Logger(subsystem: subsystem, category: "HDMI")
}
