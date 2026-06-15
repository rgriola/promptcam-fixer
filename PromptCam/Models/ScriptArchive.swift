import Foundation

/// A single archived script entry.
struct ArchivedScript: Codable, Identifiable {
    let id: UUID
    let text: String
    let savedAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.savedAt = Date()
    }

    /// Human-readable relative timestamp ("2 hours ago", "3 days ago").
    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: savedAt, relativeTo: Date())
    }

    /// First 80 characters of the script, for preview.
    var preview: String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count <= 80 { return oneLine }
        return String(oneLine.prefix(80)) + "…"
    }
}

/// Manages a rolling archive of recent scripts in UserDefaults.
///
/// - Auto-prunes entries older than 7 days on access.
/// - Caps storage at 20 entries.
/// - Archives automatically on each Compose Save.
@MainActor
struct ScriptArchive {
    private static let storageKey = "scriptArchive"
    private static let maxEntries = 20
    private static let retentionDays: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    /// Loads all non-expired archived scripts, newest first.
    static func load() -> [ArchivedScript] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let scripts = try? JSONDecoder().decode([ArchivedScript].self, from: data)
        else { return [] }

        let cutoff = Date().addingTimeInterval(-retentionDays)
        return scripts.filter { $0.savedAt > cutoff }
    }

    /// Archives a script. Deduplicates if the text matches the most recent entry.
    static func save(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var scripts = load()

        // Skip if identical to the most recent archive
        if scripts.first?.text == trimmed { return }

        scripts.insert(ArchivedScript(text: trimmed), at: 0)

        // Cap at maxEntries
        if scripts.count > maxEntries {
            scripts = Array(scripts.prefix(maxEntries))
        }

        if let data = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Deletes a specific archived script.
    static func delete(id: UUID) {
        var scripts = load()
        scripts.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Removes all archived scripts.
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
