import XCTest

@MainActor
final class TaskCheckboxUITests: XCTestCase {
    /// M8. Today's date header and task count summary, two tasks toggled independently (tapping one row never
    /// toggles the other), then an inline edit that leaves the checkbox alone, and a swipe delete.
    func testTaskFlowAddsTogglesEditsAndDeletesTasks() throws {
        let app = XCUIApplication()
        launchIsolatedApp(app)

        let expectedDate = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        XCTAssertTrue(app.staticTexts[expectedDate].waitForExistence(timeout: 10))

        let taskSummary = app.descendants(matching: .any)["task-count-summary"]
        XCTAssertTrue(taskSummary.waitForExistence(timeout: 10))
        let initialCounts = try XCTUnwrap(taskSummary.value as? String)
            .components(separatedBy: " / ")
        XCTAssertEqual(initialCounts.count, 2)
        let initialCompleted = try XCTUnwrap(Int(initialCounts[0]))
        let initialTotal = try XCTUnwrap(Int(initialCounts[1].components(separatedBy: " ")[0]))
        func counts(done: Int, of total: Int) -> String {
            "\(initialCompleted + done) / \(initialTotal + total) tasks done"
        }

        let first = "First task"
        let second = "Second task"
        addTask(first, to: app)
        assertValue(taskSummary, equals: counts(done: 0, of: 1))
        addTask(second, to: app)
        assertValue(taskSummary, equals: counts(done: 0, of: 2))
        assertValue(app.buttons[first], equals: "Not completed")
        assertValue(app.buttons[second], equals: "Not completed")

        app.buttons[first].tap()
        assertValue(app.buttons[first], equals: "Completed")
        assertValue(app.buttons[second], equals: "Not completed")
        assertValue(taskSummary, equals: counts(done: 1, of: 2))

        app.buttons[second].tap()
        assertValue(app.buttons[second], equals: "Completed")
        assertValue(app.buttons[first], equals: "Completed")
        assertValue(taskSummary, equals: counts(done: 2, of: 2))

        app.buttons[first].tap()
        assertValue(app.buttons[first], equals: "Not completed")
        assertValue(app.buttons[second], equals: "Completed")
        assertValue(taskSummary, equals: counts(done: 1, of: 2))

        app.buttons[second].tap()
        assertValue(app.buttons[second], equals: "Not completed")
        assertValue(app.buttons[first], equals: "Not completed")
        assertValue(taskSummary, equals: counts(done: 0, of: 2))

        // Editing opens the inline editor; the checkbox is a separate target, and the other task is untouched.
        let renamed = "\(first) renamed"
        app.buttons["Edit task: \(first)"].tap()
        let editor = app.textFields["task-editor:\(first)"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(" renamed\n")

        let checkbox = app.buttons[renamed]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        assertValue(checkbox, equals: "Not completed")
        assertValue(app.buttons[second], equals: "Not completed")
        checkbox.tap()
        assertValue(app.buttons[renamed], equals: "Completed")
        assertValue(app.buttons[second], equals: "Not completed")
        assertValue(taskSummary, equals: counts(done: 1, of: 2))

        app.buttons["Edit task: \(renamed)"].swipeLeft()
        let deleteButton = app.buttons["Delete task: \(renamed)"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10))
        deleteButton.tap()
        let deletedTaskControls = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", first))
        let deletionExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: deletedTaskControls
        )
        XCTAssertEqual(XCTWaiter.wait(for: [deletionExpectation], timeout: 10), .completed)
        assertValue(taskSummary, equals: counts(done: 0, of: 1))
        assertValue(app.buttons[second], equals: "Not completed")
    }

    func testLongPressingATaskRowOffersShareThenDeleteAndShareLeavesTheTaskAsItWas() throws {
        let app = XCUIApplication()
        launchIsolatedApp(app)

        let title = "Shareable task \(String(UUID().uuidString.prefix(8)))"
        addTask(title, to: app)
        app.buttons[title].tap()
        assertValue(app.buttons[title], equals: "Completed")

        // A completed Task gets the same menu: Share, then Delete.
        app.buttons["Edit task: \(title)"].press(forDuration: 1.0)
        let share = app.buttons["Share"]
        let delete = app.buttons["Delete"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(delete.exists)
        XCTAssertLessThan(share.frame.minY, delete.frame.minY)

        // Share opens the system share sheet; cancelling it leaves the Task unchanged. The sheet is
        // system UI with no public accessibility identifier, so "ActivityListView" is its internal
        // one. It is closed with its close button on iPhone; the iPad popover has none, so the test taps
        // the popover's dismiss region, again an internal identifier. A tap while the sheet is still
        // animating in can miss, so wait for the sheet to be hittable first (#165).
        // What the sheet receives is covered by TaskShareBehaviorTests.
        share.tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: sheet)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed, "the share sheet never settled")
        let close = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "close")).firstMatch
        if close.waitForExistence(timeout: 10) {
            close.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "the share sheet is still showing")
        assertValue(app.buttons[title], equals: "Completed")
    }

    /// M9. Habits on Today: the empty state and Save rules, adding, checking off and unchecking, the edit form's
    /// prefill, cancelling and confirming the delete, then weekday habits that are and aren't due today.
    func testHabitFlowAddsChecksOffEditsDeletesAndHonoursWeekdays() throws {
        let app = XCUIApplication()
        launchIsolatedApp(app)

        let calendar = Calendar.current
        let todayIndex = calendar.component(.weekday, from: .now) - 1
        let today = calendar.weekdaySymbols[todayIndex]
        let otherDay = calendar.weekdaySymbols[(todayIndex + 1) % 7]

        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
        let summary = app.descendants(matching: .any)["summary-Habits done"]
        assertValue(summary, equals: "0 / 0 habits done")

        // Save waits for a name; a daily habit checks off and unchecks.
        let field = openHabitForm(in: app)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        field.typeText("Stretch")
        tapSaveWhenEnabled(in: app)

        let circle = app.buttons["Stretch"]
        XCTAssertTrue(circle.waitForExistence(timeout: 10))
        assertValue(circle, equals: "Not completed")
        assertValue(summary, equals: "0 / 1 habits done")
        circle.tap()
        assertValue(app.buttons["Stretch"], equals: "Completed, 1 day streak")
        assertValue(summary, equals: "1 / 1 habits done")
        app.buttons["Stretch"].tap()
        assertValue(app.buttons["Stretch"], equals: "Not completed")

        // The name opens the form prefilled; the circle still checks off.
        app.buttons["Edit habit: Stretch"].tap()
        let editField = app.textFields["Habit name"]
        XCTAssertTrue(editField.waitForExistence(timeout: 10))
        XCTAssertEqual(editField.value as? String, "Stretch")
        XCTAssertTrue(app.navigationBars["Edit Habit"].exists)
        editField.tap()
        editField.typeText(" more")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Stretch more"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Stretch"].exists)
        app.buttons["Stretch more"].tap()
        assertValue(app.buttons["Stretch more"], equals: "Completed, 1 day streak")

        // Cancelling the confirmation keeps the habit; confirming deletes it and its log.
        app.buttons["Edit habit: Stretch more"].tap()
        let deleteButton = app.buttons["Delete habit"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10))
        deleteButton.tap()
        XCTAssertTrue(app.staticTexts["Delete this habit?"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Delete habit"].waitForExistence(timeout: 10))
        app.buttons["Delete habit"].tap()
        XCTAssertTrue(app.buttons["Delete habit and log"].waitForExistence(timeout: 10))
        app.buttons["Delete habit and log"].tap()
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Stretch more"].waitForNonExistence(timeout: 10))

        // A weekday habit on another day exists but isn't due, and Save needs at least one weekday.
        openHabitForm(in: app).typeText("Elsewhere")
        app.buttons["Weekdays"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save needs at least one weekday")
        app.buttons[otherDay].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Nothing due today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Elsewhere"].exists)
        assertValue(summary, equals: "0 / 0 habits done")

        // A weekday habit on today's weekday is listed and can be checked off.
        openHabitForm(in: app).typeText("Today only")
        app.buttons["Weekdays"].tap()
        app.buttons[today].tap()
        tapSaveWhenEnabled(in: app)
        let todayCircle = app.buttons["Today only"]
        XCTAssertTrue(todayCircle.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Nothing due today"].waitForNonExistence(timeout: 10))
        assertValue(summary, equals: "0 / 1 habits done")
        todayCircle.tap()
        assertValue(app.buttons["Today only"], equals: "Completed, 1 day streak")
        assertValue(summary, equals: "1 / 1 habits done")
    }

    /// Opens the new-habit form from the Add menu and returns its name field.
    @discardableResult
    private func openHabitForm(in app: XCUIApplication) -> XCUIElement {
        app.buttons["Add an item"].tap()
        app.buttons["Habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        return field
    }

    private func addTask(_ title: String, to app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(title + "\n")
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10))
    }

    private func launchIsolatedApp(_ app: XCUIApplication) {
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
    }

    /// Waits for `element`'s `value` to become `expectedValue`. A tap's effect lands after an animation and a
    /// re-render, and the CI runner is slow enough that 3 s wasn't (#165), so this allows 10 s like #164.
    private func assertValue(_ element: XCUIElement, equals expectedValue: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedValue),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
            "expected \(element) to have value \(expectedValue), has \(String(describing: element.value))"
        )
    }

    /// Save stays disabled until the typed name reaches the form, which can lag the keystrokes on the CI runner;
    /// a tap before then does nothing and the habit is never added (#165).
    private func tapSaveWhenEnabled(in app: XCUIApplication) {
        let save = app.buttons["Save"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed, "Save never became enabled")
        save.tap()
    }
}
