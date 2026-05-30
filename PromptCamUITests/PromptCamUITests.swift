import XCTest

final class PromptCamUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainScreenHasRecordingControl() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Start recording"].exists || app.buttons["Stop recording"].exists)
        XCTAssertTrue(app.buttons["Format panel"].exists)
        XCTAssertTrue(app.staticTexts["AUTO"].exists)
    }
}
