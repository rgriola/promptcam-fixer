// RecordingFormatTests.swift
// PromptCamTests
//
// Verifies RecordingFormat round-trip persistence and the .default fallback.
// Tests mutate UserDefaults.standard (which is what production code uses) and
// restore the prior value in tearDown so the test is hermetic.

import XCTest
@testable import PromptCam

final class RecordingFormatTests: XCTestCase {

    private let storageKey = "com.promptcam.recordingFormat"
    private var savedValue: Data?

    override func setUp() {
        super.setUp()
        // Snapshot any pre-existing user setting so tests don't trash it.
        savedValue = UserDefaults.standard.data(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        if let savedValue {
            UserDefaults.standard.set(savedValue, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        super.tearDown()
    }

    // MARK: - Defaults

    func testLoadSavedReturnsDefaultWhenNothingPersisted() {
        XCTAssertEqual(RecordingFormat.loadSaved(), .default)
    }

    func testDefaultIsStandardHD30() {
        XCTAssertEqual(RecordingFormat.default.resolution, .hd1080p)
        XCTAssertEqual(RecordingFormat.default.frameRate, .fps30)
        XCTAssertEqual(RecordingFormat.default.mode, .standard)
    }

    // MARK: - Round-trip

    func testSaveThenLoadReturnsSameFormat() {
        let format = RecordingFormat(resolution: .uhd4K, frameRate: .fps60, mode: .standard)
        format.save()

        XCTAssertEqual(RecordingFormat.loadSaved(), format)
    }

    func testSaveOverwritesPreviousValue() {
        RecordingFormat(resolution: .hd1080p, frameRate: .fps24, mode: .standard).save()
        let newFormat = RecordingFormat(resolution: .uhd4K, frameRate: .fps30, mode: .cinematic)
        newFormat.save()

        XCTAssertEqual(RecordingFormat.loadSaved(), newFormat)
    }

    // MARK: - Corruption resilience

    func testLoadSavedReturnsDefaultWhenStoredDataIsCorrupted() {
        // Write garbage bytes for the same key.
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        UserDefaults.standard.set(garbage, forKey: storageKey)

        XCTAssertEqual(RecordingFormat.loadSaved(), .default)
    }
}
