import Foundation

/// Centralized persistence service for `UserPreferences`.
///
/// Reads and writes a single JSON blob to UserDefaults under one key,
/// replacing the previous scatter of ~10 individual keys. All encode/decode
/// failures are logged via `Log.persistence` — corruption is no longer
/// invisible.
///
/// On first load, automatically migrates legacy keys from the old
/// `TeleprompterStyleStore` and `RecordingFormat` persistence into the
/// consolidated blob, then deletes the old keys.
struct PreferencesStore {

    // MARK: - Storage Key

    static let storageKey = "com.promptcam.userPreferences"

    // MARK: - Legacy Keys (for migration)

    private enum LegacyKey {
        // TeleprompterStyleStore keys
        static let fontSize   = "tp.fontSize"
        static let speed      = "tp.speed"
        static let textColor  = "tp.textColor"
        static let bgOpacity  = "tp.bgOpacity"
        static let alignment  = "tp.alignment"
        static let scriptText = "tp.scriptText"
        // RecordingFormat key
        static let recordingFormat = "com.promptcam.recordingFormat"

        static let all: [String] = [
            fontSize, speed, textColor, bgOpacity,
            alignment, scriptText, recordingFormat
        ]
    }

    // MARK: - Dependencies

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Loads preferences from UserDefaults.
    ///
    /// On first access, migrates from legacy keys if present.
    /// Falls back to `UserPreferences.default` if no data exists or
    /// decoding fails (with a logged error).
    func load() -> UserPreferences {
        // Try the new consolidated key first.
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                return try JSONDecoder().decode(UserPreferences.self, from: data)
            } catch {
                Log.persistence.error(
                    "Failed to decode UserPreferences: \(error.localizedDescription, privacy: .public). Falling back to defaults."
                )
                return .default
            }
        }

        // No consolidated blob — attempt legacy migration.
        let migrated = migrateFromLegacyKeys()
        if migrated != .default {
            save(migrated)
            removeLegacyKeys()
            Log.persistence.info("Migrated legacy preference keys to consolidated store.")
            return migrated
        }

        // Fresh install — no legacy keys, no new blob.
        return .default
    }

    /// Persists preferences as a single JSON blob.
    ///
    /// Encode failures are logged — the caller doesn't need to handle them.
    func save(_ preferences: UserPreferences) {
        do {
            let data = try JSONEncoder().encode(preferences)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            Log.persistence.error(
                "Failed to encode UserPreferences: \(error.localizedDescription, privacy: .public). Preferences not saved."
            )
        }
    }

    // MARK: - Legacy Migration

    /// Reads from the old per-field and per-blob keys, builds a
    /// `UserPreferences` struct, and returns it. Returns `.default`
    /// if no legacy data exists.
    private func migrateFromLegacyKeys() -> UserPreferences {
        let hasLegacyStyle = defaults.object(forKey: LegacyKey.fontSize) != nil
        let hasLegacyFormat = defaults.data(forKey: LegacyKey.recordingFormat) != nil

        guard hasLegacyStyle || hasLegacyFormat else { return .default }

        var prefs = UserPreferences.default

        // --- Teleprompter style keys ---
        if hasLegacyStyle {
            prefs.fontSize = defaults.double(forKey: LegacyKey.fontSize)
            prefs.speedPointsPerSecond = defaults.double(forKey: LegacyKey.speed)
            prefs.backgroundOpacity = defaults.double(forKey: LegacyKey.bgOpacity)

            if let color = defaults.string(forKey: LegacyKey.textColor) {
                prefs.textColor = color
            }
            if let alignment = defaults.string(forKey: LegacyKey.alignment) {
                prefs.textAlignment = alignment
            }
            if let script = defaults.string(forKey: LegacyKey.scriptText), !script.isEmpty {
                prefs.scriptText = script
            }
        }

        // --- RecordingFormat blob ---
        if let formatData = defaults.data(forKey: LegacyKey.recordingFormat) {
            do {
                prefs.recordingFormat = try JSONDecoder().decode(
                    RecordingFormat.self, from: formatData
                )
            } catch {
                Log.persistence.error(
                    "Failed to decode legacy RecordingFormat: \(error.localizedDescription, privacy: .public). Using default format."
                )
            }
        }

        return prefs
    }

    /// Removes all legacy keys after a successful migration.
    private func removeLegacyKeys() {
        for key in LegacyKey.all {
            defaults.removeObject(forKey: key)
        }
        Log.persistence.debug("Removed \(LegacyKey.all.count, privacy: .public) legacy preference keys.")
    }
}
