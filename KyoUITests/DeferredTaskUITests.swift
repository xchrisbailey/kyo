import XCTest

@MainActor
final class DeferredTaskUITests: XCTestCase {
    func testCreatingAPlannedTaskConfirmsIntoLaterWithoutChangingTaskText() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText("Call Friday")
        let schedule = app.buttons["new-task-schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        let preview = app.staticTexts["task-planned-day-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let future = Calendar.current.date(byAdding: .day, value: 7, to: Date.now)!
        let formatter = DateFormatter()
        let wheels = app.datePickers["task-planned-day-picker"].pickerWheels
        XCTAssertEqual(wheels.count, 3)
        formatter.dateFormat = "MMMM"
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = "d"
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = "yyyy"
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = nil
        formatter.dateStyle = .full
        XCTAssertEqual(preview.label, formatter.string(from: future))
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Call Friday"].exists) // label-query: future task text must be absent from Today
        app.buttons["section-header-tasks"].tap()
        XCTAssertEqual(app.buttons["section-header-tasks"].label, "Tasks, No tasks")
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["Call Friday"].waitForExistence(timeout: 5)) // label-query: task text is preserved separately from scheduling
    }

    func testCancelingDateSelectionLeavesAnUnsavedDraftThatCanBeAbandoned() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["new-task-schedule"].isEnabled)
        entry.typeText("Keep Friday in the text")
        app.buttons["new-task-schedule"].tap()
        XCTAssertTrue(app.staticTexts["task-planned-day-preview"].waitForExistence(timeout: 5))
        app.buttons["task-scheduling-cancel"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.value as? String, "Keep Friday in the text")
        XCTAssertFalse(app.buttons["Keep Friday in the text"].exists) // label-query: canceled date selection must not create a task
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["later-empty"].waitForExistence(timeout: 5))
        app.buttons["later-done"].tap()
        let cancel = app.buttons["new-task-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        app.buttons["section-header-tasks"].tap()
        XCTAssertEqual(app.buttons["section-header-tasks"].label, "Tasks, No tasks")
    }

    func testBlankEntryCreatesNothingAndTodayConfirmationPreservesPlainTextEntry() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText(" \n")
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        let summary = app.descendants(matching: .any)["task-count-summary"]
        XCTAssertEqual(summary.value as? String, "0 / 0 tasks done")

        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.typeText("Friday at 3")
        app.buttons["new-task-schedule"].tap()
        XCTAssertTrue(app.staticTexts["task-planned-day-preview"].waitForExistence(timeout: 5))
        app.buttons["task-scheduling-today"].tap()
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(app.buttons["Friday at 3"].waitForExistence(timeout: 5)) // label-query: selecting Today keeps the full task text
        XCTAssertEqual(summary.value as? String, "0 / 1 tasks done")

        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.typeText("October 16\n")
        XCTAssertTrue(app.buttons["October 16"].waitForExistence(timeout: 5)) // label-query: text-only entry never extracts a date
        XCTAssertEqual(summary.value as? String, "0 / 2 tasks done")
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["later-empty"].waitForExistence(timeout: 5))
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
