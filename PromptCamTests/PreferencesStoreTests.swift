// PreferencesStoreTests.swift
// PromptCamTests
//
// Unit tests for the consolidated PreferencesStore: round-trip, corruption
// handling, and legacy key migration.

import XCTest
@testable import PromptCam

final class PreferencesStoreTests: XCTestCase {

    /// Isolated UserDefaults suite so tests don't pollute the real defaults.
    private var testDefaults: UserDefaults!
    private var sut: PreferencesStore!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "com.promptcam.tests.prefs")!
        // Clear any leftover state from a previous run.
        testDefaults.removePersistentDomain(forName: "com.promptcam.tests.prefs")
        sut = PreferencesStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.promptcam.tests.prefs")
        testDefaults = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Round-Trip

    func testRoundTrip_encodesAndDecodes() {
        var prefs = UserPreferences.default
        prefs.fontSize = 42
        prefs.scriptText = "Test script"
        prefs.recordingFormat = RecordingFormat(resolution: .uhd4K, frameRate: .fps60, mode: .standard)

        sut.save(prefs)
        let loaded = sut.load()

        XCTAssertEqual(loaded, prefs,
                       "Preferences should survive a save/load round-trip")
    }

    // MARK: - Missing Key → Default

    func testLoad_returnsDefaultWhenNoDataExists() {
        let loaded = sut.load()

        XCTAssertEqual(loaded, .default,
                       "Fresh store with no data should return defaults")
    }

    // MARK: - Corrupt Data → Logged Error + Default

    func testLoad_returnsDefaultOnCorruptData() {
        // Write garbage data to the preferences key.
        testDefaults.set(Data("not valid json".utf8), forKey: PreferencesStore.storageKey)

        let loaded = sut.load()

        XCTAssertEqual(loaded, .default,
                       "Corrupt data should fall back to defaults (and log an error)")
    }

    // MARK: - Legacy Migration

    func testLoad_migratesLegacyStyleKeys() {
        // Seed old-style keys (simulating a pre-migration install).
        testDefaults.set(Double(48), forKey: "tp.fontSize")
        testDefaults.set(Double(80), forKey: "tp.speed")
        testDefaults.set("yellow", forKey: "tp.textColor")
        testDefaults.set(Double(0.5), forKey: "tp.bgOpacity")
        testDefaults.set("left", forKey: "tp.alignment")
        testDefaults.set("Legacy script", forKey: "tp.scriptText")

        let loaded = sut.load()

        XCTAssertEqual(loaded.fontSize, 48, "fontSize should be migrated")
        XCTAssertEqual(loaded.speedPointsPerSecond, 80, "speed should be migrated")
        XCTAssertEqual(loaded.textColor, "yellow", "textColor should be migrated")
        XCTAssertEqual(loaded.backgroundOpacity, 0.5, "bgOpacity should be migrated")
        XCTAssertEqual(loaded.textAlignment, "left", "alignment should be migrated")
        XCTAssertEqual(loaded.scriptText, "Legacy script", "scriptText should be migrated")
    }

    func testLoad_migratesLegacyRecordingFormat() {
        let format = RecordingFormat(resolution: .uhd4K, frameRate: .fps24, mode: .cinematic)
        let data = try! JSONEncoder().encode(format)
        testDefaults.set(data, forKey: "com.promptcam.recordingFormat")

        let loaded = sut.load()

        XCTAssertEqual(loaded.recordingFormat, format,
                       "RecordingFormat should be migrated from legacy key")
    }

    func testLoad_removesLegacyKeysAfterMigration() {
        // Seed a legacy key.
        testDefaults.set(Double(36), forKey: "tp.fontSize")

        _ = sut.load()

        // Legacy key should be removed.
        XCTAssertNil(testDefaults.object(forKey: "tp.fontSize"),
                     "Legacy key should be removed after migration")
        // Consolidated key should exist.
        XCTAssertNotNil(testDefaults.data(forKey: PreferencesStore.storageKey),
                        "Consolidated key should be written after migration")
    }

    func testLoad_doesNotMigrateWhenConsolidatedKeyExists() {
        // Write consolidated prefs.
        var prefs = UserPreferences.default
        prefs.fontSize = 50
        sut.save(prefs)

        // Plant a legacy key that should NOT override the consolidated data.
        testDefaults.set(Double(99), forKey: "tp.fontSize")

        let loaded = sut.load()

        XCTAssertEqual(loaded.fontSize, 50,
                       "Consolidated key should take priority over stale legacy keys")
    }

    // MARK: - Overwrite

    func testSave_overwritesPreviousData() {
        var prefs1 = UserPreferences.default
        prefs1.fontSize = 20
        sut.save(prefs1)

        var prefs2 = UserPreferences.default
        prefs2.fontSize = 60
        sut.save(prefs2)

        let loaded = sut.load()
        XCTAssertEqual(loaded.fontSize, 60,
                       "Latest save should overwrite previous data")
    }
}
