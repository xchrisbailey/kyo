import XCTest

@MainActor
final class MonthPlannedTasksUITests: XCTestCase {
    func testFuturePlannedTaskHasAccessibleReadOnlyMonthRow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText("Future Month task\n")
        let checkbox = app.buttons["Future Month task"] // label-query: the task's saved text is the subject
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        checkbox.press(forDuration: 1)
        app.buttons["task-do-later"].tap()
        let calendar = Calendar.current
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: Date.now))
        let wheels = app.datePickers["task-planned-day-picker"].pickerWheels
        XCTAssertEqual(wheels.count, 3)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: formatter.string(from: date))
        formatter.dateFormat = "d"
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: formatter.string(from: date))
        formatter.dateFormat = "yyyy"
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: formatter.string(from: date))
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(checkbox.waitForNonExistence(timeout: 10))
        app.buttons["main-view-month"].tap()
        XCTAssertTrue(app.staticTexts["month-header"].waitForExistence(timeout: 10))
        if !calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
            app.buttons["month-next"].tap()
        }
        formatter.dateFormat = "yyyy-MM-dd"
        let cell = app.buttons["month-day-\(formatter.string(from: date))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        XCTAssertTrue(cell.label.contains("1 task planned"))
        cell.tap()
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "month-summary-row-task-")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.label, "Future Month task")
        XCTAssertEqual(row.value as? String, "Planned")
        XCTAssertNotEqual(row.elementType, .button)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "month-summary-row-task-")).count, 0)
        XCTAssertFalse(app.textFields["new-task"].exists)
        XCTAssertFalse(app.buttons["task-scheduling-confirm"].exists)
    }
}
