import XCTest

@MainActor
final class HabitManagerUITests: XCTestCase {
    /// M7. Today's habits through Settings → Habits: every habit is listed with its schedule, the manager adds and
    /// edits through the form, Edit mode offers a reorder handle on every habit (the drag itself isn't exercised:
    /// on the CI simulator a synthesized drag often lifts the row without swapping it, #152), and swipe-delete
    /// asks for confirmation, cancelling keeps the habit and confirming removes it.
    func testHabitManagerListsAddsEditsReordersAndDeletesHabits() throws {
        let app = launchIsolatedApp()
        let calendar = Calendar.current
        let todayIndex = calendar.component(.weekday, from: .now) - 1
        let otherDay = calendar.weekdaySymbols[(todayIndex + 1) % 7]

        addHabitOnToday("Stretch", in: app)
        addHabitOnToday("Elsewhere", onlyOn: otherDay, in: app)
        XCTAssertFalse(app.buttons["Elsewhere"].exists, "not due today, so not on Today")

        // Settings holds the Habits entry and the Schedule group's switch; the manager lists every habit.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Habits"].exists)
        XCTAssertTrue(app.switches["Show schedule"].exists, "Settings' other entry is the Schedule group's switch")
        app.buttons["Habits"].tap()
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 10))

        let stretch = managerRow("Stretch", in: app)
        let elsewhere = managerRow("Elsewhere", in: app)
        XCTAssertTrue(stretch.waitForExistence(timeout: 10))
        XCTAssertEqual(stretch.value as? String, "Every day")
        XCTAssertTrue(elsewhere.exists)
        XCTAssertEqual(
            elsewhere.value as? String,
            "\(calendar.shortWeekdaySymbols[(todayIndex + 1) % 7]), not due today"
        )

        // Add from the manager with a weekly target.
        app.buttons["Add habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["New Habit"].exists)
        field.typeText("Journal")
        app.buttons["Weekly target"].tap()
        app.buttons["Save"].tap()

        let journal = managerRow("Journal", in: app)
        XCTAssertTrue(journal.waitForExistence(timeout: 10))
        XCTAssertEqual(journal.value as? String, "3× a week")

        // Edit it: the form is prefilled, and renaming and rescheduling shows in the manager.
        journal.tap()
        let editField = app.textFields["Habit name"]
        XCTAssertTrue(editField.waitForExistence(timeout: 10))
        XCTAssertEqual(editField.value as? String, "Journal")
        XCTAssertTrue(app.navigationBars["Edit Habit"].exists)
        editField.tap()
        editField.typeText(" daily")
        app.buttons["Every day"].tap()
        app.buttons["Save"].tap()

        let renamed = managerRow("Journal daily", in: app)
        XCTAssertTrue(renamed.waitForExistence(timeout: 10))
        XCTAssertEqual(renamed.value as? String, "Every day")
        XCTAssertTrue(managerRow("Journal", in: app).waitForNonExistence(timeout: 10))

        // Edit mode offers a reorder handle on every habit, and Done takes them away.
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Reorder Stretch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Reorder Elsewhere"].exists)
        XCTAssertTrue(app.buttons["Reorder Journal daily"].exists)
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Reorder Stretch"].waitForNonExistence(timeout: 10), "Done ends Edit mode")

        // Swipe-delete asks first. The dialog is a centered popover with no Cancel button; tapping outside
        // dismisses it and keeps the habit.
        managerRow("Stretch", in: app).swipeLeft()
        app.buttons["Delete habit: Stretch"].tap()
        XCTAssertTrue(app.staticTexts["Delete this habit?"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.4)).tap()
        XCTAssertTrue(app.staticTexts["Delete this habit?"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(managerRow("Stretch", in: app).waitForExistence(timeout: 10), "cancelling keeps the habit")

        managerRow("Stretch", in: app).swipeLeft()
        app.buttons["Delete habit: Stretch"].tap()
        XCTAssertTrue(app.buttons["Delete habit and log"].waitForExistence(timeout: 10))
        app.buttons["Delete habit and log"].tap()
        XCTAssertTrue(managerRow("Stretch", in: app).waitForNonExistence(timeout: 10))
        XCTAssertTrue(managerRow("Elsewhere", in: app).exists)
        XCTAssertTrue(managerRow("Journal daily", in: app).exists)
    }

    // MARK: Helpers

    private func managerRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.cells.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Adds a habit from Today's Add menu. Without `weekday` it's a daily habit, due today, so it waits for its row.
    private func addHabitOnToday(_ name: String, onlyOn weekday: String? = nil, in app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText(name)
        if let weekday {
            app.buttons["Weekdays"].tap()
            app.buttons[weekday].tap()
        }
        app.buttons["Save"].tap()
        if weekday == nil {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10))
        } else {
            XCTAssertTrue(field.waitForNonExistence(timeout: 10), "the form closes after Save")
        }
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
