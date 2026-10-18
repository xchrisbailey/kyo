import XCTest

@MainActor
extension XCTestCase {
    /// Projects can be managed without reserving an empty section on Today.
    func openProjects(in app: XCUIApplication) {
        let settings = app.buttons["settings-button"]
        for _ in 0..<10 where !settings.isHittable { app.scrollViews.firstMatch.swipeDown() }
        settings.tap()
        let toggle = app.switches["settings-projects-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String == "0" { toggle.switches.firstMatch.tap() }
        let projects = app.buttons["settings-all-projects"]
        XCTAssertTrue(projects.waitForExistence(timeout: 5))
        projects.tap()
        XCTAssertTrue(app.buttons["project-new"].waitForExistence(timeout: 5))
    }
}
