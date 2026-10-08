import XCTest

@MainActor
final class HabitsSheetUITests: XCTestCase {
    /// M7. The Habits sheet behind See all: the link shows only once a habit exists, every habit is listed with its
    /// schedule, the sheet adds and edits through the form, Edit mode offers a reorder handle on every habit (the
    /// drag itself isn't exercised: on the CI simulator a synthesized drag often lifts the row without swapping it,
    /// #152) and swaps the sheet's Done for its own, and swipe-delete asks for confirmation, cancelling keeps the
    /// habit and confirming removes it. Settings holds only the Schedule group.
    func testHabitsSheetListsAddsEditsReordersAndDeletesHabits() throws {
        let app = launchIsolatedApp()
        let calendar = Calendar.current
        let todayIndex = calendar.component(.weekday, from: .now) - 1
        let otherDay = calendar.weekdaySymbols[(todayIndex + 1) % 7]

        XCTAssertFalse(app.buttons["section-link-habits"].exists, "no habits, so no See all")

        addHabitOnToday("Stretch", in: app)
        XCTAssertTrue(app.buttons["section-link-habits"].waitForExistence(timeout: 10))
        addHabitOnToday("Elsewhere", onlyOn: otherDay, in: app)
        XCTAssertFalse(app.buttons["Elsewhere"].exists, "not due today, so not on Today")

        // Settings holds only the Schedule group.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["Show schedule"].exists)
        XCTAssertFalse(app.buttons["Habits"].exists, "Settings has no Habits entry")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 10))

        // See all opens the sheet, which lists every habit.
        openHabitsSheet(in: app)

        let stretch = habitRow("Stretch", in: app)
        let elsewhere = habitRow("Elsewhere", in: app)
        XCTAssertTrue(stretch.waitForExistence(timeout: 10))
        XCTAssertEqual(stretch.value as? String, "Every day")
        XCTAssertTrue(elsewhere.exists)
        XCTAssertEqual(
            elsewhere.value as? String,
            "\(calendar.shortWeekdaySymbols[(todayIndex + 1) % 7]), not due today"
        )

        // Add from the sheet with a weekly target.
        app.buttons["Add habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["New Habit"].exists)
        field.typeText("Journal")
        app.buttons["Weekly target"].tap()
        tapSaveWhenEnabled(in: app)

        let journal = habitRow("Journal", in: app)
        XCTAssertTrue(journal.waitForExistence(timeout: 10))
        XCTAssertEqual(journal.value as? String, "3× a week, 0 of 3 this week")

        // Edit it: the form is prefilled, and renaming and rescheduling shows in the sheet.
        journal.tap()
        let editField = app.textFields["Habit name"]
        XCTAssertTrue(editField.waitForExistence(timeout: 10))
        XCTAssertEqual(editField.value as? String, "Journal")
        XCTAssertTrue(app.navigationBars["Edit Habit"].exists)
        editField.tap()
        editField.typeText(" daily")
        app.buttons["Every day"].tap()
        tapSaveWhenEnabled(in: app)

        let renamed = habitRow("Journal daily", in: app)
        XCTAssertTrue(renamed.waitForExistence(timeout: 10))
        XCTAssertEqual(renamed.value as? String, "Every day")
        XCTAssertTrue(habitRow("Journal", in: app).waitForNonExistence(timeout: 10))

        // Edit mode offers a reorder handle on every habit. Its Done replaces the sheet's, so there is only one;
        // tapping it ends Edit mode and leaves the sheet open, with its own Done back.
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Reorder Stretch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Reorder Elsewhere"].exists)
        XCTAssertTrue(app.buttons["Reorder Journal daily"].exists)
        XCTAssertEqual(app.navigationBars["Habits"].buttons.matching(identifier: "Done").count, 1)
        app.navigationBars["Habits"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Reorder Stretch"].waitForNonExistence(timeout: 10), "Done ends Edit mode")
        XCTAssertTrue(app.navigationBars["Habits"].exists, "ending Edit mode leaves the sheet open")
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Habits"].buttons["Done"].exists)

        // Swipe-delete asks first. The dialog is a centered popover with no Cancel button; tapping outside
        // dismisses it and keeps the habit.
        habitRow("Stretch", in: app).swipeLeft()
        app.buttons["Delete habit: Stretch"].tap()
        XCTAssertTrue(app.staticTexts["Delete this habit?"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.4)).tap()
        XCTAssertTrue(app.staticTexts["Delete this habit?"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(habitRow("Stretch", in: app).waitForExistence(timeout: 10), "cancelling keeps the habit")

        habitRow("Stretch", in: app).swipeLeft()
        app.buttons["Delete habit: Stretch"].tap()
        XCTAssertTrue(app.buttons["Delete habit and log"].waitForExistence(timeout: 10))
        app.buttons["Delete habit and log"].tap()
        XCTAssertTrue(habitRow("Stretch", in: app).waitForNonExistence(timeout: 10))
        XCTAssertTrue(habitRow("Elsewhere", in: app).exists)
        XCTAssertTrue(habitRow("Journal daily", in: app).exists)

        // Done closes the sheet.
        app.navigationBars["Habits"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Habits"].waitForNonExistence(timeout: 10))
    }

    /// Deleting from a habit's edit form: Delete habit asks first, confirming pops back to the sheet without the row.
    func testDeletingAHabitFromItsEditFormRemovesItFromTheSheet() throws {
        let app = launchIsolatedApp()
        addHabitOnToday("Stretch", in: app)
        addHabitOnToday("Journal", in: app)
        openHabitsSheet(in: app)

        let stretch = habitRow("Stretch", in: app)
        XCTAssertTrue(stretch.waitForExistence(timeout: 10))
        stretch.tap()
        XCTAssertTrue(app.navigationBars["Edit Habit"].waitForExistence(timeout: 10))
        app.buttons["Delete habit"].tap()
        XCTAssertTrue(app.buttons["Delete habit and log"].waitForExistence(timeout: 10))
        app.buttons["Delete habit and log"].tap()

        XCTAssertTrue(app.navigationBars["Edit Habit"].waitForNonExistence(timeout: 10), "the form pops after deleting")
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 10))
        XCTAssertTrue(habitRow("Stretch", in: app).waitForNonExistence(timeout: 10))
        XCTAssertTrue(habitRow("Journal", in: app).exists)
    }

    /// A check-off on Today shows as a streak on the habit's row in the Habits sheet, whose rows have no check circle.
    func testARowShowsItsStreakAfterACheckOffOnToday() throws {
        let app = launchIsolatedApp()
        addHabitOnToday("Stretch", in: app)
        let circle = app.buttons["Stretch"]
        circle.tap()
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Completed, 1 day streak"), object: circle)
        XCTAssertEqual(XCTWaiter.wait(for: [checked], timeout: 10), .completed, "the check-off never registered")

        openHabitsSheet(in: app)
        let row = habitRow("Stretch", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.value as? String, "Every day, 1 day streak")
        let cell = app.cells.containing(NSPredicate(format: "identifier == %@", row.identifier)).firstMatch
        XCTAssertEqual(cell.buttons.count, 1, "the row's own button is all its cell holds: no check circle")
    }

    // MARK: Helpers

    /// Opens the Habits sheet from the Habits section's See all, not Memos' (a user with a habit and a memo has two).
    private func openHabitsSheet(in app: XCUIApplication) {
        let seeAll = app.buttons["section-link-habits"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 10))
        seeAll.tap()
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 10))
    }

    private func habitRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'habit-row-' AND label == %@", name)).firstMatch
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
        tapSaveWhenEnabled(in: app)
        if weekday == nil {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10))
        } else {
            XCTAssertTrue(field.waitForNonExistence(timeout: 10), "the form closes after Save")
        }
    }

    /// Save stays disabled until the typed name reaches the form, which can lag the keystrokes on the CI runner;
    /// a tap before then does nothing and the habit is never added.
    private func tapSaveWhenEnabled(in app: XCUIApplication) {
        let save = app.buttons["Save"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, "Save never became enabled")
        save.tap()
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
