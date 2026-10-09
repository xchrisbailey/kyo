import XCTest

@MainActor
final class PalettePreferenceUITests: XCTestCase {
    /// Names the defaults suite this test's launches keep the palette preference in, so the relaunch
    /// reads what the first launch wrote and no other test does.
    private let suite = "kyo.theme.ui-tests.\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testThePickedPaletteIsStillSelectedAfterARelaunch() {
        let app = launchApp()
        openSettings(in: app)
        let palette = app.segmentedControls["palette-picker"]
        XCTAssertTrue(palette.buttons["System"].isSelected, "a fresh launch follows the device")
        XCTAssertFalse(palette.buttons["Dark"].isSelected)

        palette.buttons["Dark"].tap()

        XCTAssertTrue(waitForSelected(palette.buttons["Dark"]), "a tap applies the preference at once")
        XCTAssertFalse(palette.buttons["System"].isSelected)
        relaunch(app)
        openSettings(in: app)

        XCTAssertTrue(waitForSelected(app.segmentedControls["palette-picker"].buttons["Dark"]))
        XCTAssertFalse(app.segmentedControls["palette-picker"].buttons["System"].isSelected)
    }

    func testTheControlIsLabelledPalette() {
        let app = launchApp()
        openSettings(in: app)

        XCTAssertEqual(app.segmentedControls["palette-picker"].label, "Palette")
        XCTAssertEqual(app.segmentedControls["palette-picker"].buttons.count, 3)
    }

    // MARK: Helpers

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_THEME_SUITE"] = suite
        app.launch()
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.segmentedControls["palette-picker"].waitForExistence(timeout: 10))
    }

    private func waitForSelected(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Terminates the app, waits for the process to be gone, then launches it again with the same launch environment.
    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app is still running after terminate")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "the app isn't in the foreground after launch")
    }
}
