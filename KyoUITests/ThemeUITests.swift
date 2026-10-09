import XCTest

@MainActor
final class ThemeUITests: XCTestCase {
    /// Names the defaults suite this test's launches keep the theme in, so the relaunch reads what the
    /// first launch wrote and no other test does.
    private let suite = "kyo.theme.ui-tests.\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testThePickedThemeIsStillSelectedAfterARelaunch() {
        let app = launchApp()
        openSettings(in: app)
        XCTAssertTrue(waitForSelected(app.buttons["theme-card-kyo"]), "a fresh launch starts on the Kyo theme")
        XCTAssertFalse(app.buttons["theme-card-neko"].isSelected)

        app.buttons["theme-card-neko"].tap()

        XCTAssertTrue(waitForSelected(app.buttons["theme-card-neko"]), "a tap applies the theme at once")
        XCTAssertFalse(app.buttons["theme-card-kyo"].isSelected)
        relaunch(app)
        openSettings(in: app)

        XCTAssertTrue(waitForSelected(app.buttons["theme-card-neko"]))
        XCTAssertFalse(app.buttons["theme-card-kyo"].isSelected)
    }

    func testEachCardReadsAsOneButtonWithTheThemeName() {
        let app = launchApp()
        openSettings(in: app)

        XCTAssertEqual(app.buttons["theme-card-kyo"].label, "Kyo")
        XCTAssertEqual(app.buttons["theme-card-neko"].label, "Neko")
    }

    func testNekoHeadersGrowWithTheDeviceTextSize() {
        let app = launchApp()
        openSettings(in: app)
        app.buttons["theme-card-neko"].tap()
        XCTAssertTrue(waitForSelected(app.buttons["theme-card-neko"]))
        app.buttons["settings-done"].tap()
        let normal = monthHeaderHeight(in: app)

        relaunch(app, textSize: "UICTContentSizeCategoryXXXL")
        let large = monthHeaderHeight(in: app)

        XCTAssertGreaterThan(large, normal, "a Geist Mono header scales with the text size")
    }

    // MARK: Helpers

    private func monthHeaderHeight(in app: XCUIApplication) -> CGFloat {
        app.buttons["main-view-month"].tap()
        let header = app.staticTexts["month-header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        return header.frame.height
    }

    private func launchApp(textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_THEME_SUITE"] = suite
        app.launch()
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["theme-card-kyo"].waitForExistence(timeout: 10))
    }

    private func waitForSelected(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Terminates the app, waits for the process to be gone, then launches it again with the same launch environment.
    private func relaunch(_ app: XCUIApplication, textSize: String? = nil) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app is still running after terminate")
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "the app isn't in the foreground after launch")
    }
}
