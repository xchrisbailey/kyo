import XCTest

@MainActor
final class TaskCheckboxUITests: XCTestCase {
    func testTodayShowsTheCurrentLocalDateAndCurrentDayTaskCounts() throws {
        let app = XCUIApplication()
        launchIsolatedApp(app)

        let expectedDate = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        XCTAssertTrue(app.staticTexts[expectedDate].waitForExistence(timeout: 3))

        let taskSummary = app.descendants(matching: .any)["task-count-summary"]
        XCTAssertTrue(taskSummary.waitForExistence(timeout: 3))
        let initialCounts = try XCTUnwrap(taskSummary.value as? String)
            .components(separatedBy: " / ")
        XCTAssertEqual(initialCounts.count, 2)
        let initialCompleted = try XCTUnwrap(Int(initialCounts[0]))
        let initialTotal = try XCTUnwrap(Int(initialCounts[1].components(separatedBy: " ")[0]))

        let title = "Current day task \(String(UUID().uuidString.prefix(8)))"
        addTask(title, to: app)
        XCTAssertEqual(taskSummary.value as? String, "\(initialCompleted) / \(initialTotal + 1) tasks done")
        let taskCheckbox = app.buttons[title]
        assertCheckboxValue(taskCheckbox, equals: "Not completed")
        taskCheckbox.tap()
        assertCheckboxValue(app.buttons[title], equals: "Completed")
        XCTAssertEqual(taskSummary.value as? String, "\(initialCompleted + 1) / \(initialTotal + 1) tasks done")
    }

    func testCompletingMultipleTasksAndReopeningOne() throws {
        let app = XCUIApplication()
        launchIsolatedApp(app)

        let runID = String(UUID().uuidString.prefix(8))
        let firstTitle = "First checkbox task \(runID)"
        let secondTitle = "Second checkbox task \(runID)"
        addTask(firstTitle, to: app)
        addTask(secondTitle, to: app)

        let firstCheckbox = app.buttons[firstTitle]
        let secondCheckbox = app.buttons[secondTitle]
        XCTAssertTrue(firstCheckbox.waitForExistence(timeout: 3))
        XCTAssertTrue(secondCheckbox.exists)

        firstCheckbox.tap()
        assertCheckboxValue(app.buttons[firstTitle], equals: "Completed")

        app.buttons[secondTitle].tap()
        assertCheckboxValue(app.buttons[secondTitle], equals: "Completed")

        app.buttons[firstTitle].tap()
        assertCheckboxValue(app.buttons[firstTitle], equals: "Not completed")
    }

    func testEditingTaskKeepsCheckboxSeparateAndSwipeDeletesTask() throws {
        let app = XCUIApplication()
        launchIsolatedApp(app)

        let runID = String(UUID().uuidString.prefix(8))
        let originalTitle = "Editable task \(runID)"
        let editedTitle = "\(originalTitle) renamed"
        addTask(originalTitle, to: app)

        app.buttons["Edit task: \(originalTitle)"].tap()
        let editor = app.textFields["task-editor:\(originalTitle)"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText(" renamed\n")

        let checkbox = app.buttons[editedTitle]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 3))
        assertCheckboxValue(checkbox, equals: "Not completed")
        checkbox.tap()
        assertCheckboxValue(app.buttons[editedTitle], equals: "Completed")

        app.buttons["Edit task: \(editedTitle)"].swipeLeft()
        let deleteButton = app.buttons["Delete task: \(editedTitle)"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()
        let deletedTaskControls = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", runID))
        let deletionExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: deletedTaskControls
        )
        XCTAssertEqual(XCTWaiter.wait(for: [deletionExpectation], timeout: 3), .completed)
    }

    func testAddingAndCheckingOffAHabit() throws {
        let app = XCUIApplication()
        launchIsolatedApp(app)

        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 3))
        let summary = app.descendants(matching: .any)["summary-Habits done"]
        XCTAssertEqual(summary.value as? String, "0 / 0 habits done")

        app.buttons["Add an item"].tap()
        app.buttons["Habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        field.typeText("Stretch")
        app.buttons["Save"].tap()

        let circle = app.buttons["Stretch"]
        XCTAssertTrue(circle.waitForExistence(timeout: 3))
        assertCheckboxValue(circle, equals: "Not completed")
        XCTAssertEqual(summary.value as? String, "0 / 1 habits done")
        circle.tap()
        assertCheckboxValue(app.buttons["Stretch"], equals: "Completed")
        XCTAssertEqual(summary.value as? String, "1 / 1 habits done")
        app.buttons["Stretch"].tap()
        assertCheckboxValue(app.buttons["Stretch"], equals: "Not completed")
    }

    func testCreatingAWeekdayHabitThroughTheForm() throws {
        let app = XCUIApplication()
        launchIsolatedApp(app)

        let calendar = Calendar.current
        let todayIndex = calendar.component(.weekday, from: .now) - 1
        let today = calendar.weekdaySymbols[todayIndex]
        let otherDay = calendar.weekdaySymbols[(todayIndex + 1) % 7]
        let summary = app.descendants(matching: .any)["summary-Habits done"]

        // A weekday habit on another day exists but isn't due.
        openHabitForm(in: app)
        app.textFields["Habit name"].typeText("Elsewhere")
        app.buttons["Weekdays"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save needs at least one weekday")
        app.buttons[otherDay].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Nothing due today"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Elsewhere"].exists)
        XCTAssertEqual(summary.value as? String, "0 / 0 habits done")

        // A weekday habit on today's weekday is listed and can be checked off.
        openHabitForm(in: app)
        app.textFields["Habit name"].typeText("Today only")
        app.buttons["Weekdays"].tap()
        app.buttons[today].tap()
        app.buttons["Save"].tap()
        let circle = app.buttons["Today only"]
        XCTAssertTrue(circle.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Nothing due today"].exists)
        XCTAssertEqual(summary.value as? String, "0 / 1 habits done")
        circle.tap()
        assertCheckboxValue(app.buttons["Today only"], equals: "Completed")
        XCTAssertEqual(summary.value as? String, "1 / 1 habits done")
    }

    private func openHabitForm(in app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Habit"].tap()
        XCTAssertTrue(app.textFields["Habit name"].waitForExistence(timeout: 3))
    }

    private func addTask(_ title: String, to app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(title + "\n")
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3))
    }

    private func launchIsolatedApp(_ app: XCUIApplication) {
        app.launchEnvironment["KYO_TASK_STORAGE_KEY"] = "KyoUITests.\(UUID().uuidString)"
        app.launch()
    }

    private func assertCheckboxValue(_ checkbox: XCUIElement, equals expectedValue: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedValue),
            object: checkbox
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }
}
