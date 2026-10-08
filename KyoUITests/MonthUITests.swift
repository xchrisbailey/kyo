import XCTest

/// The bottom bar's switch between Today and Month, and what keeps running underneath while Month is showing.
@MainActor
final class MonthUITests: XCTestCase {
    /// Today's cell identifier, as the grid names it, for the device's current day.
    private func dayIdentifier(offsetFromToday offset: Int = 0) -> String {
        let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "month-day-%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func testSwitchingToMonthAndBackKeepsTodaysTypedTaskAndOpensMonthOnTodayEachTime() throws {
        let app = launchApp()
        let today = app.buttons["main-view-today"]
        let month = app.buttons["main-view-month"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertEqual(month.label, "Month")
        XCTAssertTrue(today.isSelected)
        XCTAssertFalse(month.isSelected)

        // A task typed on Today and not submitted.
        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Buy milk")

        month.tap()

        XCTAssertTrue(app.staticTexts["month-header"].waitForExistence(timeout: 10))
        XCTAssertTrue(month.isSelected)
        XCTAssertFalse(today.isSelected)
        XCTAssertTrue(today.exists && month.exists, "the bar stays on Month")
        XCTAssertTrue(app.staticTexts["month-summary-empty"].exists)
        XCTAssertEqual(app.staticTexts["month-summary-empty"].label, "Nothing on this day")
        XCTAssertTrue(app.descendants(matching: .any)["month-legend"].exists)
        XCTAssertFalse(app.textFields["New task"].exists)
        let todayCell = app.buttons[dayIdentifier()]
        XCTAssertTrue(todayCell.exists)
        XCTAssertTrue(todayCell.label.contains("Today"), todayCell.label)
        XCTAssertTrue(todayCell.isSelected)

        // Another day takes the selection and the Day summary's heading.
        let titleOnToday = app.staticTexts["month-summary-title"].label
        let other = app.buttons[dayIdentifier(offsetFromToday: Calendar.current.component(.day, from: .now) == 1 ? 1 : -1)]
        other.tap()
        XCTAssertTrue(other.isSelected)
        XCTAssertFalse(todayCell.isSelected)
        XCTAssertNotEqual(app.staticTexts["month-summary-title"].label, titleOnToday)

        // Back on Today, the draft is as it was left.
        today.tap()
        let draft = app.textFields["New task"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertEqual(draft.value as? String, "Buy milk")

        // Month opens on Today again every time.
        month.tap()
        XCTAssertTrue(todayCell.waitForExistence(timeout: 10))
        XCTAssertTrue(todayCell.isSelected)

        // + → Task from Month goes to Today and focuses the task field, draft intact.
        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let returned = app.textFields["New task"]
        XCTAssertTrue(returned.waitForExistence(timeout: 10))
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(returned.value as? String, "Buy milk")
        let hasFocus = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hasFocus, object: returned)], timeout: 10), .completed)
    }

    func testMemoSheetsOpenOverMonthAndLeaveYouThere() throws {
        let app = launchApp()
        let month = app.buttons["main-view-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        month.tap()
        XCTAssertTrue(app.staticTexts["month-header"].waitForExistence(timeout: 10))

        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        XCTAssertTrue(app.textFields["Memo text"].waitForExistence(timeout: 10))

        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["month-header"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["main-view-month"].isSelected)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
