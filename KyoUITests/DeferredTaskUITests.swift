import XCTest

@MainActor
final class DeferredTaskUITests: XCTestCase {
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
