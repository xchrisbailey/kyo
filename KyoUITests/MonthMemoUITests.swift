import XCTest

/// Memos in Month: a memo written on Today is marked in Month and opens from Today's Day summary.
@MainActor
final class MonthMemoUITests: XCTestCase {
    func testAMemoWrittenOnTodayOpensFromMonthsDaySummaryAndEditsShowThereWhenItCloses() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()

        app.buttons["add-item"].tap()
        app.buttons["add-item-written-memo"].tap()
        let compose = app.textFields["memo-compose-text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        compose.typeText("Weekend idea")
        app.buttons["memo-compose-save"].tap()
        let memosHeader = app.buttons["section-header-memos"]
        XCTAssertTrue(memosHeader.waitForExistence(timeout: 10))
        XCTAssertEqual(memosHeader.label, "Memos, 1 memo")

        app.buttons["main-view-month"].tap()
        XCTAssertTrue(app.staticTexts["month-header"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["month-summary-empty"].exists)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let todayCell = app.buttons[String(format: "month-day-%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)]
        XCTAssertTrue(todayCell.label.hasSuffix("1 memo"), todayCell.label)

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'month-summary-row-memo-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.label, "Weekend idea")
        row.tap()

        let editor = app.textFields["memo-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("Edited: ")
        app.buttons["memo-close"].tap()

        XCTAssertTrue(app.staticTexts["month-header"].waitForExistence(timeout: 10))
        let edited = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'month-summary-row-memo-'")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 10))
        let updated = NSPredicate(format: "label BEGINSWITH 'Edited: '")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated, object: edited)], timeout: 10), .completed)
    }
}
