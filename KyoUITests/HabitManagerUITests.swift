import XCTest

@MainActor
final class HabitManagerUITests: XCTestCase {
    func testGearOpensSettingsWithHabitsAndTheScheduleGroupAndTheManagerListsEveryHabit() throws {
        let app = launchIsolatedApp()
        let calendar = Calendar.current
        let todayIndex = calendar.component(.weekday, from: .now) - 1
        let otherDay = calendar.weekdaySymbols[(todayIndex + 1) % 7]

        addHabitOnToday("Stretch", in: app)
        app.buttons["Add an item"].tap()
        app.buttons["Habit"].tap()
        app.textFields["Habit name"].typeText("Elsewhere")
        app.buttons["Weekdays"].tap()
        app.buttons[otherDay].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Stretch"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Elsewhere"].exists, "not due today, so not on Today")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Habits"].exists)
        XCTAssertTrue(app.switches["Show schedule"].exists, "Settings' other entry is the Schedule group's switch")
        app.buttons["Habits"].tap()
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 3))

        let stretch = managerRow("Stretch", in: app)
        let elsewhere = managerRow("Elsewhere", in: app)
        XCTAssertTrue(stretch.waitForExistence(timeout: 3))
        XCTAssertEqual(stretch.value as? String, "Every day")
        XCTAssertTrue(elsewhere.exists)
        XCTAssertEqual(
            elsewhere.value as? String,
            "\(calendar.shortWeekdaySymbols[(todayIndex + 1) % 7]), not due today"
        )
    }

    func testAddingAndEditingFromTheManager() throws {
        let app = launchIsolatedApp()
        openManager(in: app)

        app.buttons["Add habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["New Habit"].exists)
        field.typeText("Journal")
        app.buttons["Weekly target"].tap()
        app.buttons["Save"].tap()

        let row = managerRow("Journal", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(row.value as? String, "3× a week")

        row.tap()
        let editField = app.textFields["Habit name"]
        XCTAssertTrue(editField.waitForExistence(timeout: 3))
        XCTAssertEqual(editField.value as? String, "Journal")
        XCTAssertTrue(app.navigationBars["Edit Habit"].exists)
        editField.tap()
        editField.typeText(" daily")
        app.buttons["Every day"].tap()
        app.buttons["Save"].tap()

        let renamed = managerRow("Journal daily", in: app)
        XCTAssertTrue(renamed.waitForExistence(timeout: 3))
        XCTAssertEqual(renamed.value as? String, "Every day")
        XCTAssertFalse(managerRow("Journal", in: app).exists)
    }

    func testDeletingFromTheEditFormAsksForConfirmation() throws {
        let app = launchIsolatedApp()
        addHabitOnToday("Stretch", in: app)
        openManager(in: app)

        managerRow("Stretch", in: app).tap()
        XCTAssertTrue(app.buttons["Delete habit"].waitForExistence(timeout: 3))
        app.buttons["Delete habit"].tap()
        XCTAssertTrue(app.staticTexts["Delete this habit?"].waitForExistence(timeout: 3))
        app.buttons["Delete habit and log"].tap()

        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 3))
        XCTAssertFalse(managerRow("Stretch", in: app).exists)
    }

    func testSwipeDeleteConfirmsThenRemovesTheHabit() throws {
        let app = launchIsolatedApp()
        addHabitOnToday("Stretch", in: app)
        addHabitOnToday("Read", in: app)
        openManager(in: app)

        managerRow("Stretch", in: app).swipeLeft()
        app.buttons["Delete habit: Stretch"].tap()
        XCTAssertTrue(app.staticTexts["Delete this habit?"].waitForExistence(timeout: 3))
        // The dialog is a centered popover with no Cancel button; tapping outside dismisses it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.4)).tap()
        XCTAssertTrue(app.staticTexts["Delete this habit?"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(managerRow("Stretch", in: app).waitForExistence(timeout: 3), "cancelling keeps the habit")

        managerRow("Stretch", in: app).swipeLeft()
        app.buttons["Delete habit: Stretch"].tap()
        app.buttons["Delete habit and log"].tap()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: managerRow("Stretch", in: app)
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed)
        XCTAssertTrue(managerRow("Read", in: app).exists)
    }

    /// Edit mode offers a reorder handle on every habit. The drag itself isn't exercised here: on
    /// the CI simulator a synthesized drag often lifts the row without swapping it (#152). Moving,
    /// persisting the order, and Today following it are covered by HabitOrderBehaviorTests.
    func testEditModeOffersAReorderHandleOnEveryHabit() throws {
        let app = launchIsolatedApp()
        addHabitOnToday("First", in: app)
        addHabitOnToday("Second", in: app)
        openManager(in: app)

        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Reorder First"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Reorder Second"].exists)

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Reorder First"].waitForNonExistence(timeout: 3), "Done ends Edit mode")
    }

    // MARK: Helpers

    private func managerRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.cells.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func openManager(in app: XCUIApplication) {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["Habits"].tap()
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 3))
    }

    private func addHabitOnToday(_ name: String, in app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(name)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3))
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
