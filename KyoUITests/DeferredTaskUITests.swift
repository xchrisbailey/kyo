import XCTest

@MainActor
final class DeferredTaskUITests: XCTestCase {
    func testLaterEditsTextWithoutChangingItsPlannedDayAndCanCancelAnEdit() {
        let app = XCUIApplication()
        let plannedDay = openLaterWithDeferredTask(app, text: "Original task")
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "later-task-edit-")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        guard edit.exists else { return }
        edit.tap()
        let entry = app.textFields["later-task-editor"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Original task".count) + "Changed task")
        app.buttons["later-edit-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Original task"].exists) // label-query: cancellation preserves saved text
        edit.tap()
        entry.tap()
        entry.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Original task".count) + "Changed task")
        app.buttons["later-edit-save"].tap()
        XCTAssertTrue(app.staticTexts["Changed task"].waitForExistence(timeout: 5)) // label-query: saved edit is the subject
        let day = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "later-task-planned-day-")).firstMatch
        XCTAssertEqual(day.label, plannedDay)
        app.buttons["later-done"].tap()
        XCTAssertFalse(app.buttons["Changed task"].exists) // label-query: edited future task stays off Today
    }

    @discardableResult
    private func openLaterWithDeferredTask(_ app: XCUIApplication, text: String) -> String {
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText(text + "\n")
        let task = app.buttons[text]
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1)
        app.buttons["task-do-later"].tap()
        let future = Calendar.current.date(byAdding: .day, value: 7, to: Date.now)!
        chooseDate(future, in: app)
        let preview = app.staticTexts["task-planned-day-preview"].label
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        return preview
    }

    private func chooseDate(_ date: Date, in app: XCUIApplication) {
        let wheels = app.datePickers["task-planned-day-picker"].pickerWheels
        XCTAssertEqual(wheels.count, 3)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: formatter.string(from: date))
        formatter.dateFormat = "MMMM"
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: formatter.string(from: date))
        formatter.dateFormat = "d"
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: formatter.string(from: date))
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
