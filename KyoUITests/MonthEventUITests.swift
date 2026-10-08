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

        // Two all-day and three timed events, read as the Schedule reads them on Today.
        let section = app.descendants(matching: .any)["month-summary-section-events"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["All day: Sam's birthday"].exists)
        XCTAssertTrue(app.buttons["All day: Holiday"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Standup, Work calendar, ended")).firstMatch.exists)
        let running = app.buttons.matching(NSPredicate(format: "label == %@", "Now, Design review, Work calendar")).firstMatch
        XCTAssertTrue(running.exists)

        running.tap()

        let title = app.descendants(matching: .any)["event-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Design review")
        app.buttons["event-detail-done"].tap()
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["month-header"].exists, "Done leaves the user on Month")
    }
}
