// May 30, 2026 - 11:35pm - GitHub Copilot (Claude Opus 4.7)
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
