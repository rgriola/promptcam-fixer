// July 17, 2026 - GitHub Copilot - Extracted teleprompter style persistence from CameraViewModel
import Foundation

/// Persists and restores teleprompter style settings (font size, speed, color,
/// background opacity, alignment, and script text) via `UserDefaults`.
/// Extracted from `CameraViewModel` so the coordinator stays thin.
struct TeleprompterStyleStore {
    private enum StyleKey {
        static let fontSize   = "tp.fontSize"
        static let speed      = "tp.speed"
        static let textColor  = "tp.textColor"
        static let bgOpacity  = "tp.bgOpacity"
        static let alignment  = "tp.alignment"
        static let scriptText = "tp.scriptText"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Persists the style fields of `config`. The script text is only saved when
    /// it differs from the default placeholder, so a fresh install still shows
    /// the onboarding hint text.
    func save(_ config: TeleprompterConfig) {
        defaults.set(config.fontSize,              forKey: StyleKey.fontSize)
        defaults.set(config.speedPointsPerSecond,  forKey: StyleKey.speed)
        defaults.set(config.textColor.rawValue,    forKey: StyleKey.textColor)
        defaults.set(config.backgroundOpacity,     forKey: StyleKey.bgOpacity)
        defaults.set(config.textAlignment.rawValue, forKey: StyleKey.alignment)
        // Only persist the script when it differs from the default placeholder
        // so a fresh install still shows the onboarding hint text.
        if config.text != TeleprompterConfig.default.text {
            defaults.set(config.text, forKey: StyleKey.scriptText)
        }
    }

    /// Returns `config` with any previously-saved style settings applied.
    /// Defaults are left untouched until a value has actually been saved.
    func applyingSaved(to config: TeleprompterConfig) -> TeleprompterConfig {
        // Only override defaults if a value has actually been saved previously.
        guard defaults.object(forKey: StyleKey.fontSize) != nil else { return config }

        var config = config
        config.fontSize             = defaults.double(forKey: StyleKey.fontSize)
        config.speedPointsPerSecond = defaults.double(forKey: StyleKey.speed)
        config.backgroundOpacity    = defaults.double(forKey: StyleKey.bgOpacity)
        if let raw = defaults.string(forKey: StyleKey.textColor),
           let color = TeleprompterTextColor(rawValue: raw) {
            config.textColor = color
        }
        if let raw = defaults.string(forKey: StyleKey.alignment),
           let alignment = TeleprompterTextAlignment(rawValue: raw) {
            config.textAlignment = alignment
        }
        config = config.clamped
        // Restore the saved script. If no script has been saved yet (fresh
        // install or user cleared it), fall back to the default hint text.
        if let saved = defaults.string(forKey: StyleKey.scriptText), !saved.isEmpty {
            config.text = saved
        } else {
            config.text = TeleprompterConfig.default.text
        }
        Log.viewmodel.debug("loadStylePreferences restored fontSize=\(Int(config.fontSize), privacy: .public) speed=\(Int(config.speedPointsPerSecond), privacy: .public) color=\(config.textColor.rawValue, privacy: .public) bgOpacity=\(config.backgroundOpacity, privacy: .public) scriptLen=\(config.text.count, privacy: .public)")
        return config
    }
}
