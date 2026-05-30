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
        XCTAssertFalse(TeleprompterConfig.default.text.isEmpty)
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
