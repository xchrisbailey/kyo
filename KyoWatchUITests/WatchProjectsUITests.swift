import XCTest

@MainActor
final class WatchProjectsUITests: XCTestCase {
    func testProjectsSectionStartsExpandedAndRemembersCollapseAfterRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_COLLAPSED_SECTIONS_SUITE"] = "kyo.watch-projects.ui-tests.\(UUID().uuidString)"
        app.launch()

        let tasks = app.buttons["section-header-tasks"]
        XCTAssertTrue(tasks.waitForExistence(timeout: 10))
        tasks.tap()
        let projects = app.buttons["section-header-projects"]
        scrollUntilVisible(projects, in: app)
        XCTAssertTrue(projects.exists)
        XCTAssertEqual(projects.value as? String, "expanded")
        let empty = app.staticTexts["projects-empty"]
        scrollUntilVisible(empty, in: app)
        XCTAssertEqual(empty.label, "No project tasks for today")
        projects.tap()
        XCTAssertEqual(projects.value as? String, "collapsed")
        app.terminate()
        app.launch()
        scrollUntilVisible(projects, in: app)
        XCTAssertEqual(projects.value as? String, "collapsed")
        XCTAssertFalse(empty.exists)
    }

    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.exists {
            app.swipeUp()
        }
    }
}
