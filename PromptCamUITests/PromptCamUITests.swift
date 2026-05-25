import XCTest

final class PromptCamUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainScreenHasRecordingControl() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Record"].exists || app.buttons["Stop"].exists)
    }
}
