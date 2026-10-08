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

    /// A cell identifier for a day of the month `monthOffset` months from the current one.
    private func dayIdentifier(inMonthOffset monthOffset: Int, day: Int) -> String {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: monthOffset, to: .now) ?? .now)
        parts.day = day
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

    func testMonthAndTodayEachOpenAtTheTopWhateverTheOtherWasScrolledTo() throws {
        // At an accessibility text size Month is taller than the screen too, so it can't hide behind a clamped offset.
        let app = launchApp(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let month = app.buttons["main-view-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        for index in 1...3 { addTask("Task \(index)", to: app) }
        app.swipeUp()
        app.swipeUp()
        XCTAssertFalse(app.descendants(matching: .any)["task-count-summary"].isHittable, "Today is scrolled away from its top")

        month.tap()

        XCTAssertTrue(app.staticTexts["month-header"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["month-header"].isHittable)
        XCTAssertTrue(app.buttons[dayIdentifier()].isHittable)

        app.buttons["main-view-today"].tap()

        let summary = app.descendants(matching: .any)["task-count-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.isHittable)

        // + → Task from Month scrolls Today to the new field, past the tasks above it.
        month.tap()
        XCTAssertTrue(app.staticTexts["month-header"].waitForExistence(timeout: 10))
        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let isShown = NSPredicate(format: "isHittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isShown, object: field)], timeout: 10), .completed)
    }

    func testChevronsAndSwipesMoveBetweenMonthsAndJumpBackReturnsToTodayWithTheCurrentMonth() throws {
        let app = launchApp()
        let month = app.buttons["main-view-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        month.tap()
        let header = app.staticTexts["month-header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let currentHeader = header.label
        let previous = app.buttons["month-previous"]
        let next = app.buttons["month-next"]
        let jumpBack = app.buttons["month-jump-back"]
        XCTAssertEqual(previous.label, "Previous month")
        XCTAssertEqual(next.label, "Next month")
        XCTAssertFalse(jumpBack.exists, "the current month needs no way back")

        next.tap()
        XCTAssertNotEqual(header.label, currentHeader)
        XCTAssertTrue(jumpBack.waitForExistence(timeout: 10))
        XCTAssertEqual(jumpBack.label, "Back to current month")
        XCTAssertFalse(app.buttons[dayIdentifier()].exists, "Today's cell is in the other month")
        XCTAssertTrue(app.buttons[dayIdentifier(inMonthOffset: 1, day: 1)].isSelected, "the 1st stands in for a selection outside the month")

        // A swipe on the grid moves a month too: left is forward, right is back.
        let grid = app.descendants(matching: .any)["month-grid"]
        XCTAssertTrue(grid.exists)
        let shownAfterNext = header.label
        grid.swipeLeft()
        XCTAssertTrue(waitForLabel(of: header, toDiffer: shownAfterNext))
        grid.swipeRight()
        XCTAssertTrue(waitForLabel(of: header, toEqual: shownAfterNext))

        previous.tap()
        XCTAssertEqual(header.label, currentHeader)
        XCTAssertFalse(jumpBack.exists)

        previous.tap()
        XCTAssertTrue(jumpBack.waitForExistence(timeout: 10))
        jumpBack.tap()
        XCTAssertEqual(header.label, currentHeader)
        XCTAssertFalse(jumpBack.exists)
        XCTAssertTrue(app.buttons[dayIdentifier()].isSelected)
    }

    private func waitForLabel(of element: XCUIElement, toDiffer label: String) -> Bool {
        let changed = NSPredicate(format: "label != %@", label)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: element)], timeout: 10) == .completed
    }

    private func waitForLabel(of element: XCUIElement, toEqual label: String) -> Bool {
        let matches = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: element)], timeout: 10) == .completed
    }

    private func addTask(_ title: String, to app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText(title + "\n")
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10))
    }

    private func launchApp(textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
