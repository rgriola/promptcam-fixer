import XCTest

final class PromptCamUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainScreenHasRecordingControl() {
        let app = XCUIApplication()
        app.launchArguments.append("-uitest-skip-onboarding")
        app.launch()

        let recordButton = app.buttons["Start recording"].firstMatch
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5),
                      "Expected the record button to appear after launch.")

        XCTAssertTrue(app.buttons["Format panel"].exists,
                      "Expected the Format panel button in the top controls.")

        let lockBadge = app.buttons["Focus and exposure lock"]
        XCTAssertTrue(lockBadge.exists, "Expected the focus/exposure lock badge.")
        XCTAssertEqual(lockBadge.value as? String, "AUTO",
                       "Expected the lock badge to start in AUTO state.")
    }
}
