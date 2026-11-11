@testable import PromptCam

// PromptCam Unit Tests
// Updated June 1, 2026 — aligned with current TeleprompterGeometry API
// (progress-based pipeline was removed in Phase 5)
// June 4, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add textColor/backgroundOpacity to init calls after Phase 2 model expansion
// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add textAlignment tests
import XCTest

// MARK: - TeleprompterConfig Tests

final class TeleprompterConfigTests: XCTestCase {
    func testClampedConfigLimitsFontAndSpeed() {
        let config = TeleprompterConfig(
            text: "Sample",
            speedPointsPerSecond: 300,
            fontSize: 8,
            textColor: .white,
            backgroundOpacity: 0.15,
            textAlignment: .center,
        )

        let clamped = config.clamped

        XCTAssertEqual(clamped.speedPointsPerSecond, 150)
        XCTAssertEqual(clamped.fontSize, 16)
    }

    func testDefaultConfigHasExpectedValues() {
        XCTAssertEqual(TeleprompterConfig.default.speedPointsPerSecond, 35)
        XCTAssertEqual(TeleprompterConfig.default.fontSize, 30)
        XCTAssertEqual(TeleprompterConfig.default.textAlignment, .center)
        XCTAssertFalse(TeleprompterConfig.default.text.isEmpty)
    }

    func testClampedConfigSnapsToEvenFontSize() {
        let oddConfig = TeleprompterConfig(
            text: "Test",
            speedPointsPerSecond: 50,
            fontSize: 25,
            textColor: .white,
            backgroundOpacity: 0.15,
            textAlignment: .center,
        )
        XCTAssertEqual(oddConfig.clamped.fontSize, 26) // rounds to nearest even
    }

    func testClampedConfigClampsSpeedLowerBound() {
        let lowSpeed = TeleprompterConfig(
            text: "Test",
            speedPointsPerSecond: 1,
            fontSize: 30,
            textColor: .white,
            backgroundOpacity: 0.15,
            textAlignment: .center,
        )
        XCTAssertEqual(lowSpeed.clamped.speedPointsPerSecond, 5)
    }

    func testClampedConfigClampsFontUpperBound() {
        let bigFont = TeleprompterConfig(
            text: "Test",
            speedPointsPerSecond: 35,
            fontSize: 100,
            textColor: .white,
            backgroundOpacity: 0.15,
            textAlignment: .center,
        )
        XCTAssertEqual(bigFont.clamped.fontSize, 72)
    }

    func testDefaultConfigTextColorIsWhite() {
        XCTAssertEqual(TeleprompterConfig.default.textColor, .white)
    }

    func testClampedConfigClampsBackgroundOpacity() {
        let overOpaque = TeleprompterConfig(
            text: "Test",
            speedPointsPerSecond: 35,
            fontSize: 30,
            textColor: .white,
            backgroundOpacity: 1.5,
            textAlignment: .center,
        )
        XCTAssertEqual(overOpaque.clamped.backgroundOpacity, 0.85, accuracy: 0.001)

        let negative = TeleprompterConfig(
            text: "Test",
            speedPointsPerSecond: 35,
            fontSize: 30,
            textColor: .white,
            backgroundOpacity: -0.5,
            textAlignment: .center,
        )
        XCTAssertEqual(negative.clamped.backgroundOpacity, 0.0, accuracy: 0.001)
    }

    func testTextAlignmentCycle() {
        // 3-state cycle: center → left → right → center
        XCTAssertEqual(TeleprompterTextAlignment.center.next, .left)
        XCTAssertEqual(TeleprompterTextAlignment.left.next, .right)
        XCTAssertEqual(TeleprompterTextAlignment.right.next, .center)
    }

    func testTextAlignmentSwiftUIMapping() {
        XCTAssertEqual(TeleprompterTextAlignment.center.swiftUIAlignment, .center)
        XCTAssertEqual(TeleprompterTextAlignment.left.swiftUIAlignment, .leading)
        XCTAssertEqual(TeleprompterTextAlignment.right.swiftUIAlignment, .trailing)
    }

    func testTextAlignmentIcons() {
        XCTAssertEqual(TeleprompterTextAlignment.center.iconName, "text.aligncenter")
        XCTAssertEqual(TeleprompterTextAlignment.left.iconName, "text.alignleft")
        XCTAssertEqual(TeleprompterTextAlignment.right.iconName, "text.alignright")
    }

    // MARK: - All Caps

    func testDefaultConfigDoesNotUseAllCaps() {
        XCTAssertFalse(TeleprompterConfig.default.usesAllCaps)
        XCTAssertEqual(TeleprompterConfig.default.displayText, TeleprompterConfig.default.text)
    }

    func testDisplayTextUppercasesWithoutChangingSourceText() {
        let script = "Hello there.\nSecond line, with punctuation!"
        var config = TeleprompterConfig(
            text: script,
            speedPointsPerSecond: 35,
            fontSize: 30,
            textColor: .white,
            backgroundOpacity: 0.15,
            textAlignment: .center,
        )

        config.usesAllCaps = true

        XCTAssertEqual(config.displayText, "HELLO THERE.\nSECOND LINE, WITH PUNCTUATION!")
        XCTAssertEqual(config.text, script, "Source script must keep its original casing")
    }

    func testDisplayTextIsReversible() {
        var config = TeleprompterConfig(
            text: "Mixed Case Script",
            speedPointsPerSecond: 35,
            fontSize: 30,
            textColor: .white,
            backgroundOpacity: 0.15,
            textAlignment: .center,
        )

        config.usesAllCaps = true
        config.usesAllCaps = false

        XCTAssertEqual(config.displayText, "Mixed Case Script")
    }

    func testAllCapsChangesMeasurementKey() {
        var config = TeleprompterConfig(
            text: "Mixed Case Script",
            speedPointsPerSecond: 35,
            fontSize: 30,
            textColor: .white,
            backgroundOpacity: 0.15,
            textAlignment: .center,
        )
        let normalKey = TextMeasureKey(text: config.displayText, fontSize: config.fontSize, width: 300)

        config.usesAllCaps = true
        let capsKey = TextMeasureKey(text: config.displayText, fontSize: config.fontSize, width: 300)

        XCTAssertNotEqual(normalKey, capsKey, "Re-measurement must fire so wrapping stays correct")
    }

    func testClampedPreservesAllCaps() {
        var config = TeleprompterConfig(
            text: "Test",
            speedPointsPerSecond: 300,
            fontSize: 8,
            textColor: .white,
            backgroundOpacity: 0.15,
            textAlignment: .center,
        )
        config.usesAllCaps = true

        XCTAssertTrue(config.clamped.usesAllCaps)
    }
}

// MARK: - All Caps Persistence Tests

final class TeleprompterAllCapsPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "TeleprompterAllCapsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testAllCapsRoundTrips() {
        let store = TeleprompterStyleStore(defaults: defaults)
        var config = TeleprompterConfig.default
        config.usesAllCaps = true

        store.save(config)

        XCTAssertTrue(store.applyingSaved(to: .default).usesAllCaps)
    }

    func testAllCapsOffRoundTrips() {
        let store = TeleprompterStyleStore(defaults: defaults)
        var config = TeleprompterConfig.default
        config.usesAllCaps = true
        store.save(config)

        config.usesAllCaps = false
        store.save(config)

        XCTAssertFalse(store.applyingSaved(to: .default).usesAllCaps)
    }

    func testMissingAllCapsKeyDefaultsToOff() {
        // Simulates styles saved before this setting existed.
        defaults.set(40.0, forKey: "tp.fontSize")
        defaults.set(35.0, forKey: "tp.speed")

        let restored = TeleprompterStyleStore(defaults: defaults).applyingSaved(to: .default)

        XCTAssertFalse(restored.usesAllCaps)
        XCTAssertEqual(restored.fontSize, 40)
    }
}

// MARK: - TeleprompterGeometry Tests

final class TeleprompterGeometryTests: XCTestCase {
    /// Reference geometry: 500pt viewport, 2000pt text, 30pt font, 16pt padding.
    private func makeGeometry(textHeight: CGFloat = 2000) -> TeleprompterGeometry {
        TeleprompterGeometry(viewportHeight: 500, textHeight: textHeight, fontSize: 30, verticalPadding: 16)
    }

    func testLineHeightUsesScaleFactor() {
        let geometry = makeGeometry()
        // lineHeight = fontSize * 1.4 = 30 * 1.4 = 42
        XCTAssertEqual(geometry.lineHeight, 42, accuracy: 0.001)
    }

    func testStartOffsetCentersFirstLineInViewport() {
        let geometry = makeGeometry()
        // startOffset = centerOffset = viewportH/2 - padding - lineH/2
        // = 250 - 16 - 21 = 213
        XCTAssertEqual(geometry.startOffset, 213, accuracy: 0.001)
    }

    func testCenterOffsetMatchesStartOffset() {
        let geometry = makeGeometry()
        XCTAssertEqual(geometry.centerOffset, geometry.startOffset, accuracy: 0.001)
    }

    func testScrollStopOffsetPlacesLastLineAboveViewport() {
        let geometry = makeGeometry()
        // scrollStopOffset = -(textHeight + padding) = -(2000 + 16) = -2016
        XCTAssertEqual(geometry.scrollStopOffset, -2016, accuracy: 0.001)
    }

    func testDragCeilingPreventsFirstLineBelowViewport() {
        let geometry = makeGeometry()
        // dragCeiling = viewportHeight - lineHeight = 500 - 42 = 458
        XCTAssertEqual(geometry.dragCeiling, 458, accuracy: 0.001)
    }

    func testStartOffsetIsAboveScrollStopOffset() {
        let geometry = makeGeometry()
        // The script starts at a positive offset (first line centered) and
        // scrolls to a negative offset (last line exits top).
        XCTAssertGreaterThan(geometry.startOffset, geometry.scrollStopOffset)
    }

    func testDragCeilingIsAboveStartOffset() {
        let geometry = makeGeometry()
        // dragCeiling (458) should be above startOffset (213) — user can drag
        // first line further down from center toward the bottom.
        XCTAssertGreaterThan(geometry.dragCeiling, geometry.startOffset)
    }

    func testGeometryWithShortText() {
        // Short script that fits within the viewport.
        let geometry = makeGeometry(textHeight: 80)
        // scrollStopOffset = -(80 + 16) = -96
        XCTAssertEqual(geometry.scrollStopOffset, -96, accuracy: 0.001)
        // startOffset unchanged (centers first line regardless of text length)
        XCTAssertEqual(geometry.startOffset, 213, accuracy: 0.001)
        // Scroll range still valid (start > stop)
        XCTAssertGreaterThan(geometry.startOffset, geometry.scrollStopOffset)
    }

    func testGeometryWithMinimalText() {
        // Edge case: text is only one line tall.
        let geometry = makeGeometry(textHeight: 1)
        XCTAssertEqual(geometry.scrollStopOffset, -17, accuracy: 0.001)
        XCTAssertGreaterThan(geometry.dragCeiling, geometry.scrollStopOffset)
    }
}

// MARK: - CameraService Lock Outcome Tests

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
