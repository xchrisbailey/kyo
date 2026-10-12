import XCTest

@MainActor
final class DeferredTaskUITests: XCTestCase {
    func testQuickChoicesPreviewFullDatesAndOnlyConfirmMovesTaskToLater() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText("Quick choices task\n")
        let task = app.buttons["Quick choices task"] // label-query: task text is the subject of the flow
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1)
        app.buttons["task-do-later"].tap()
        let weekday = app.buttons["task-scheduling-weekday"]
        XCTAssertTrue(weekday.waitForExistence(timeout: 5))
        XCTAssertEqual(weekday.label, "Weekday")
        weekday.tap()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let day = calendar.component(.weekday, from: today)
        let weekdayChoice = app.buttons["task-scheduling-weekday-\(day)"]
        XCTAssertTrue(weekdayChoice.waitForExistence(timeout: 5))
        XCTAssertEqual(weekdayChoice.label, calendar.weekdaySymbols[day - 1])
        weekdayChoice.tap()
        let preview = app.staticTexts["task-planned-day-preview"]
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .full
        XCTAssertEqual(preview.label, formatter.string(from: today))
        let week = app.buttons["task-scheduling-one-week"]
        XCTAssertEqual(week.label, "One week out")
        week.tap()
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: today))
        XCTAssertEqual(preview.label, formatter.string(from: nextWeek))
        let month = app.buttons["task-scheduling-one-month"]
        XCTAssertEqual(month.label, "One month out")
        month.tap()
        let nextMonth = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: today))
        XCTAssertEqual(preview.label, formatter.string(from: nextMonth))
        app.buttons["task-scheduling-cancel"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.press(forDuration: 1)
        app.buttons["task-do-later"].tap()
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        XCTAssertEqual(preview.label, formatter.string(from: nextWeek))
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["Quick choices task"].waitForExistence(timeout: 5)) // label-query: saved task text remains intact
    }

    func testDoLaterCancellationAndConfirmedDateMoveTaskToLaterAndBack() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText("Deferred task\n")
        let task = app.buttons["Deferred task"] // label-query: task text is the subject of the flow
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1)
        let laterAction = app.buttons["task-do-later"]
        XCTAssertTrue(laterAction.waitForExistence(timeout: 5))
        laterAction.tap()
        XCTAssertTrue(app.staticTexts["task-planned-day-preview"].waitForExistence(timeout: 5))
        app.buttons["task-scheduling-cancel"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.press(forDuration: 1)
        laterAction.tap()
        let future = Calendar.current.date(byAdding: .day, value: 7, to: Date.now)!
        let formatter = DateFormatter()
        let picker = app.datePickers["task-planned-day-picker"]
        let wheels = picker.pickerWheels
        XCTAssertEqual(wheels.count, 3)
        formatter.dateFormat = "MMMM"
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = "d"
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = "yyyy"
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: formatter.string(from: future))
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["Deferred task"].waitForExistence(timeout: 5)) // label-query: saved task text remains intact
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-bring-to-today-")).firstMatch.tap()
        app.buttons["later-done"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(task.value as? String, "Not completed")
    }
}
