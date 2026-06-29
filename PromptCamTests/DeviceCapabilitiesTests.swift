// DeviceCapabilitiesTests.swift
// PromptCamTests
//
// Verifies DeviceCapabilities.isSupported / adjusted clamping rules and the
// derived resolutions(for:) / frameRates(for:) helpers used by the Format
// Picker. No hardware is touched — capabilities are constructed in-memory.

import XCTest
@testable import PromptCam

final class DeviceCapabilitiesTests: XCTestCase {

    // MARK: - Fixtures

    /// Capabilities that mimic a device supporting:
    ///   Standard:  1080p @ 30/60, 4K @ 30
    ///   Cinematic: 1080p @ 30 only
    private let fullCapabilities = DeviceCapabilities(
        supportsCinematicMode: true,
        standardFormats: [
            RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .standard),
            RecordingFormat(resolution: .hd1080p, frameRate: .fps60, mode: .standard),
            RecordingFormat(resolution: .uhd4K, frameRate: .fps30, mode: .standard)
        ],
        cinematicFormats: [
            RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .cinematic)
        ]
    )

    /// Capabilities for a device without cinematic support.
    private let standardOnlyCapabilities = DeviceCapabilities(
        supportsCinematicMode: false,
        standardFormats: [
            RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .standard),
            RecordingFormat(resolution: .hd1080p, frameRate: .fps60, mode: .standard)
        ],
        cinematicFormats: []
    )

    // MARK: - resolutions(for:)

    func testResolutionsForStandardReturnsUniqueValues() {
        let resolutions = fullCapabilities.resolutions(for: .standard)
        XCTAssertEqual(resolutions, [.hd1080p, .uhd4K])
    }

    func testResolutionsForCinematicWhenSupported() {
        XCTAssertEqual(fullCapabilities.resolutions(for: .cinematic), [.hd1080p])
    }

    func testResolutionsForCinematicWhenUnsupportedIsEmpty() {
        XCTAssertTrue(standardOnlyCapabilities.resolutions(for: .cinematic).isEmpty)
    }

    // MARK: - frameRates(for:)

    func testFrameRatesForStandardReturnsUniqueValues() {
        let rates = fullCapabilities.frameRates(for: .standard)
        XCTAssertEqual(Set(rates), Set([.fps30, .fps60]))
    }

    func testFrameRatesForResolutionFiltersToResolutionOnly() {
        // 4K only supports 30fps in our fixture.
        XCTAssertEqual(
            fullCapabilities.frameRates(for: .standard, resolution: .uhd4K),
            [.fps30]
        )
        // 1080p supports both.
        XCTAssertEqual(
            Set(fullCapabilities.frameRates(for: .standard, resolution: .hd1080p)),
            Set([.fps30, .fps60])
        )
    }

    // MARK: - isSupported

    func testIsSupportedReturnsTrueForValidStandardFormat() {
        let format = RecordingFormat(resolution: .uhd4K, frameRate: .fps30, mode: .standard)
        XCTAssertTrue(fullCapabilities.isSupported(format))
    }

    func testIsSupportedReturnsFalseForInvalidFrameRateAtResolution() {
        // 4K @ 60 is not in the fixture.
        let format = RecordingFormat(resolution: .uhd4K, frameRate: .fps60, mode: .standard)
        XCTAssertFalse(fullCapabilities.isSupported(format))
    }

    func testIsSupportedReturnsFalseForCinematicWhenCinematicUnsupported() {
        let format = RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .cinematic)
        XCTAssertFalse(standardOnlyCapabilities.isSupported(format))
    }

    // MARK: - adjusted

    func testAdjustedReturnsSameFormatWhenAlreadySupported() {
        let format = RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .standard)
        XCTAssertEqual(fullCapabilities.adjusted(format), format)
    }

    func testAdjustedFallsBackToStandardWhenCinematicUnsupported() {
        let cinematic = RecordingFormat(resolution: .hd1080p, frameRate: .fps30, mode: .cinematic)
        let adjusted = standardOnlyCapabilities.adjusted(cinematic)
        XCTAssertEqual(adjusted.mode, .standard)
    }

    func testAdjustedClampsResolutionToFirstSupportedWhenInvalid() {
        // Cinematic in fixture only supports 1080p; ask for 4K cinematic.
        let invalid = RecordingFormat(resolution: .uhd4K, frameRate: .fps30, mode: .cinematic)
        let adjusted = fullCapabilities.adjusted(invalid)
        XCTAssertEqual(adjusted.resolution, .hd1080p)
        XCTAssertEqual(adjusted.mode, .cinematic)
    }

    func testAdjustedClampsFrameRateToOneValidForResolution() {
        // 4K @ 60 is not valid; should clamp fps to a valid value for 4K.
        let invalid = RecordingFormat(resolution: .uhd4K, frameRate: .fps60, mode: .standard)
        let adjusted = fullCapabilities.adjusted(invalid)
        XCTAssertEqual(adjusted.resolution, .uhd4K)
        XCTAssertEqual(adjusted.frameRate, .fps30)
    }
}
