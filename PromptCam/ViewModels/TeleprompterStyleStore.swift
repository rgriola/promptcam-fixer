// July 17, 2026 - GitHub Copilot - Extracted teleprompter style persistence from CameraViewModel
// July 17, 2026 - Refactored to delegate to PreferencesStore (consolidated Codable blob)
import Foundation

/// Persists and restores teleprompter style settings (font size, speed, color,
/// background opacity, alignment, and script text) via the consolidated
/// `PreferencesStore`.
///
/// Public API is unchanged — callers still call `save(_:)` and
/// `applyingSaved(to:)`. Internally, the store reads/writes through
/// `PreferencesStore` using a single JSON blob instead of 6 individual keys.
struct TeleprompterStyleStore {

    private let store: PreferencesStore

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
    }

    /// Persists the style fields of `config`. The script text is only saved when
    /// it differs from the default placeholder, so a fresh install still shows
    /// the onboarding hint text.
    func save(_ config: TeleprompterConfig) {
        var prefs = store.load()
        prefs.fontSize = config.fontSize
        prefs.speedPointsPerSecond = config.speedPointsPerSecond
        prefs.textColor = config.textColor.rawValue
        prefs.backgroundOpacity = config.backgroundOpacity
        prefs.textAlignment = config.textAlignment.rawValue
        // Only persist the script when it differs from the default placeholder
        // so a fresh install still shows the onboarding hint text.
        if config.text != TeleprompterConfig.default.text {
            prefs.scriptText = config.text
        } else {
            prefs.scriptText = nil
        }
        store.save(prefs)
    }

    /// Returns `config` with any previously-saved style settings applied.
    /// Defaults are left untouched until a value has actually been saved.
    func applyingSaved(to config: TeleprompterConfig) -> TeleprompterConfig {
        let prefs = store.load()

        // If we're on defaults (fresh install, no saved prefs), return as-is.
        guard prefs != .default else { return config }

        var config = config
        config.fontSize = prefs.fontSize
        config.speedPointsPerSecond = prefs.speedPointsPerSecond
        config.backgroundOpacity = prefs.backgroundOpacity
        if let color = TeleprompterTextColor(rawValue: prefs.textColor) {
            config.textColor = color
        }
        if let alignment = TeleprompterTextAlignment(rawValue: prefs.textAlignment) {
            config.textAlignment = alignment
        }
        config = config.clamped
        // Restore the saved script. If no script has been saved yet (fresh
        // install or user cleared it), fall back to the default hint text.
        if let saved = prefs.scriptText, !saved.isEmpty {
            config.text = saved
        } else {
            config.text = TeleprompterConfig.default.text
        }
        Log.viewmodel.debug("loadStylePreferences restored fontSize=\(Int(config.fontSize), privacy: .public) speed=\(Int(config.speedPointsPerSecond), privacy: .public) color=\(config.textColor.rawValue, privacy: .public) bgOpacity=\(config.backgroundOpacity, privacy: .public) scriptLen=\(config.text.count, privacy: .public)")
        return config
    }
}
