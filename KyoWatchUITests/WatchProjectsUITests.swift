import XCTest

@MainActor
final class WatchProjectsUITests: XCTestCase {
    func testAnEmptyProjectsSectionIsAbsentWithEitherPreference() {
        for enabled in ["0", "1"] {
            let app = XCUIApplication()
            app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
            app.launchEnvironment["KYO_PROJECTS_ENABLED"] = enabled
            app.launch()
            XCTAssertTrue(app.buttons["section-header-tasks"].waitForExistence(timeout: 10))
            app.swipeUp()
            XCTAssertFalse(app.buttons["section-header-projects"].exists)
            XCTAssertFalse(app.staticTexts["projects-empty"].exists)
            app.terminate()
        }
    }
}
