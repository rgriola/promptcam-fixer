// RecordingFormatTests.swift
// PromptCamTests
//
// Verifies RecordingFormat persistence via the consolidated PreferencesStore
// and the .default fallback. Uses an isolated UserDefaults suite for hermeticity.

import XCTest
@testable import PromptCam

final class RecordingFormatTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var store: PreferencesStore!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "com.promptcam.tests.format")!
        testDefaults.removePersistentDomain(forName: "com.promptcam.tests.format")
        store = PreferencesStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.promptcam.tests.format")
        testDefaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testLoadReturnsDefaultWhenNothingPersisted() {
        let prefs = store.load()
        XCTAssertEqual(prefs.recordingFormat, .default)
    }

    func testDefaultIsStandardHD30() {
        XCTAssertEqual(RecordingFormat.default.resolution, .hd1080p)
        XCTAssertEqual(RecordingFormat.default.frameRate, .fps30)
        XCTAssertEqual(RecordingFormat.default.mode, .standard)
    }

    // MARK: - Round-trip

    func testSaveThenLoadReturnsSameFormat() {
        let format = RecordingFormat(resolution: .uhd4K, frameRate: .fps60, mode: .standard)
        var prefs = store.load()
        prefs.recordingFormat = format
        store.save(prefs)

        let loaded = store.load()
        XCTAssertEqual(loaded.recordingFormat, format)
    }

    func testSaveOverwritesPreviousValue() {
        var prefs = store.load()
        prefs.recordingFormat = RecordingFormat(resolution: .hd1080p, frameRate: .fps24, mode: .standard)
        store.save(prefs)

        let newFormat = RecordingFormat(resolution: .uhd4K, frameRate: .fps30, mode: .cinematic)
        prefs.recordingFormat = newFormat
        store.save(prefs)

        let loaded = store.load()
        XCTAssertEqual(loaded.recordingFormat, newFormat)
    }

    // MARK: - Corruption resilience

    func testLoadReturnsDefaultWhenStoredDataIsCorrupted() {
        // Write garbage bytes for the consolidated key.
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        testDefaults.set(garbage, forKey: PreferencesStore.storageKey)

        let loaded = store.load()
        XCTAssertEqual(loaded.recordingFormat, .default,
                       "Corrupt data should fall back to default format")
    }

    // MARK: - Legacy Migration

    func testLoadMigratesLegacyRecordingFormatKey() {
        let format = RecordingFormat(resolution: .uhd4K, frameRate: .fps24, mode: .cinematic)
        let data = try! JSONEncoder().encode(format)
        testDefaults.set(data, forKey: "com.promptcam.recordingFormat")

        let loaded = store.load()
        XCTAssertEqual(loaded.recordingFormat, format,
                       "Legacy recording format key should be migrated")
    }
}
