// May 31, 2026 - 10:30pm - GitHub Copilot (Claude Opus 4.7)
import XCTest
@testable import PromptCam

final class TeleprompterConfigTests: XCTestCase {
    func testClampedConfigLimitsFontAndSpeed() {
        let config = TeleprompterConfig(text: "Sample", speedPointsPerSecond: 300, fontSize: 8)

        let clamped = config.clamped

        XCTAssertEqual(clamped.speedPointsPerSecond, 150)
        XCTAssertEqual(clamped.fontSize, 16)
    }

    func testDefaultConfigHasExpectedValues() {
        XCTAssertEqual(TeleprompterConfig.default.speedPointsPerSecond, 35)
        XCTAssertEqual(TeleprompterConfig.default.fontSize, 30)
        XCTAssertEqual(TeleprompterConfig.default.startOffsetProgress, 1.0)
        XCTAssertFalse(TeleprompterConfig.default.text.isEmpty)
    }

    func testClampedConfigLimitsStartOffsetProgressRange() {
        let lowConfig = TeleprompterConfig(text: "Sample", speedPointsPerSecond: 35, fontSize: 30, startOffsetProgress: -2)
        let highConfig = TeleprompterConfig(text: "Sample", speedPointsPerSecond: 35, fontSize: 30, startOffsetProgress: 2)

        XCTAssertEqual(lowConfig.clamped.startOffsetProgress, 0)
        XCTAssertEqual(highConfig.clamped.startOffsetProgress, 1)
    }
}

final class TeleprompterGeometryTests: XCTestCase {
    // Reference geometry: 500pt viewport, 2000pt text, 30pt font, 16pt padding.
    private func makeGeometry(textHeight: CGFloat = 2000) -> TeleprompterGeometry {
        TeleprompterGeometry(viewportHeight: 500, textHeight: textHeight, fontSize: 30, verticalPadding: 16)
    }

    func testStartOffsetPlacesFirstLineFullyBelowViewport() {
        let geometry = makeGeometry()
        // startOffset = viewportHeight - padding = 500 - 16 = 484 (first line off-screen below)
        XCTAssertEqual(geometry.startOffset, 484, accuracy: 0.001)
    }

    func testManualEndOffsetPlacesLastLineFullyAboveViewport_TallText() {
        let geometry = makeGeometry()
        // manualEndOffset = padding - textHeight = 16 - 2000 = -1984 (last line off-screen above)
        XCTAssertEqual(geometry.manualEndOffset, -1984, accuracy: 0.001)
    }

    func testManualEndOffsetIsValidForShortText() {
        // Short script (fits in viewport): travel must still be positive and start > end.
        let geometry = makeGeometry(textHeight: 104)
        // manualEndOffset = 16 - 104 = -88
        XCTAssertEqual(geometry.manualEndOffset, -88, accuracy: 0.001)
        XCTAssertGreaterThan(geometry.startOffset, geometry.manualEndOffset)
        XCTAssertGreaterThan(geometry.manualTravel, 0)
    }

    func testCenterOffsetPlacesFirstLineAtViewportVerticalMidpoint() {
        let geometry = makeGeometry()
        // centerOffset = viewportHeight/2 - padding - lineHeight/2 = 250 - 16 - 21 = 213
        XCTAssertEqual(geometry.centerOffset, 213, accuracy: 0.001)
    }

    func testAutoScrollFloorMatchesManualEndOffset() {
        let geometry = makeGeometry()
        // Autoplay stops at the same place manual swipe stops: last line at top.
        XCTAssertEqual(geometry.autoScrollFloor, geometry.manualEndOffset, accuracy: 0.001)
    }

    func testOffsetForProgressEndpointsMatchBoundaries() {
        let geometry = makeGeometry()
        XCTAssertEqual(geometry.offset(forProgress: 1), geometry.startOffset, accuracy: 0.001)
        XCTAssertEqual(geometry.offset(forProgress: 0), geometry.manualEndOffset, accuracy: 0.001)
    }

    func testOffsetForProgressClampsOutOfRangeValues() {
        let geometry = makeGeometry()
        XCTAssertEqual(geometry.offset(forProgress: 2), geometry.startOffset, accuracy: 0.001)
        XCTAssertEqual(geometry.offset(forProgress: -1), geometry.manualEndOffset, accuracy: 0.001)
    }

    func testProgressForOffsetRoundTrips() {
        let geometry = makeGeometry()
        let midOffset = geometry.offset(forProgress: 0.42)
        XCTAssertEqual(geometry.progress(forOffset: midOffset), 0.42, accuracy: 0.0001)
    }

    func testCenterProgressFallsInsideManualRange_TallText() {
        let geometry = makeGeometry()
        XCTAssertGreaterThanOrEqual(geometry.centerProgress, 0)
        XCTAssertLessThanOrEqual(geometry.centerProgress, 1)
        XCTAssertEqual(geometry.offset(forProgress: geometry.centerProgress), geometry.centerOffset, accuracy: 0.001)
    }

    func testCenterProgressFallsInsideManualRange_ShortText() {
        let geometry = makeGeometry(textHeight: 104)
        // Round-trip must hold for short text too — this was the regression that
        // caused the reset button to snap to progress 0 instead of center.
        XCTAssertGreaterThan(geometry.centerProgress, 0)
        XCTAssertLessThan(geometry.centerProgress, 1)
        XCTAssertEqual(geometry.offset(forProgress: geometry.centerProgress), geometry.centerOffset, accuracy: 0.001)
    }

    func testManualTravelIsPositiveWhenTextExceedsViewport() {
        let geometry = makeGeometry()
        XCTAssertGreaterThan(geometry.manualTravel, 0)
    }
}

final class CameraServiceLockOutcomeTests: XCTestCase {
    func testLockOutcomeReturnsFullLockWhenBothCapabilitiesExist() {
        let outcome = CameraService.lockOutcome(supportsFocusLock: true, supportsExposureLock: true)

        XCTAssertEqual(outcome, .afAeLocked)
    }

    func testLockOutcomeReturnsAeFallbackWhenOnlyExposureLockExists() {
        let outcome = CameraService.lockOutcome(supportsFocusLock: false, supportsExposureLock: true)

        XCTAssertEqual(outcome, .aeLocked)
    }

    func testLockOutcomeReturnsAfOnlyWhenOnlyFocusLockExists() {
        let outcome = CameraService.lockOutcome(supportsFocusLock: true, supportsExposureLock: false)

        XCTAssertEqual(outcome, .afLocked)
    }

    func testLockOutcomeReturnsUnsupportedWhenNeitherLockExists() {
        let outcome = CameraService.lockOutcome(supportsFocusLock: false, supportsExposureLock: false)

        XCTAssertEqual(outcome, .unsupported)
    }
}

final class CameraServicePreferredCameraSelectionTests: XCTestCase {
    func testPreferredCameraSelectionDefaultsToFrontWhenAvailable() {
        let selection = CameraService.preferredCameraSelection(frontAvailable: true, backAvailable: true)

        XCTAssertEqual(selection, .front)
    }

    func testPreferredCameraSelectionFallsBackToBackWhenFrontUnavailable() {
        let selection = CameraService.preferredCameraSelection(frontAvailable: false, backAvailable: true)

        XCTAssertEqual(selection, .back)
    }

    func testPreferredCameraSelectionReturnsUnavailableWhenNoCameraExists() {
        let selection = CameraService.preferredCameraSelection(frontAvailable: false, backAvailable: false)

        XCTAssertEqual(selection, .unavailable)
    }
}
