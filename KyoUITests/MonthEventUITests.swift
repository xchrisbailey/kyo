import XCTest

/// Events in Month, on the fake calendar's seeded day with its clock at 10:30.
@MainActor
final class MonthEventUITests: XCTestCase {
    func testTodaysDaySummaryListsTheScheduleAndAnEventOpensItsDetails() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_FAKE_CALENDAR"] = "full"
        app.launch()
        let month = app.buttons["main-view-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        month.tap()

        // Two all-day and three timed events, read as the Schedule reads them on Today. A row's identifier
        // ends in its occurrence date, which a test can't know, so rows are found by the event's id.
        func row(_ eventID: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "month-summary-row-event-\(eventID)-")).firstMatch
        }
        XCTAssertTrue(row("birthday").exists)
        XCTAssertEqual(row("birthday").label, "All day: Sam's birthday")
        XCTAssertEqual(row("holiday").label, "All day: Holiday")
        XCTAssertEqual(row("standup").label, "9:30 AM, Standup, Work calendar, ended".replacingOccurrences(of: " AM", with: "\u{202F}AM"))
        let running = row("review")
        XCTAssertEqual(running.label, "Now, Design review, Work calendar")

        running.tap()

        let title = app.descendants(matching: .any)["event-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Design review")
        app.buttons["event-detail-done"].tap()
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["month-header"].exists, "Done leaves the user on Month")
    }
}
