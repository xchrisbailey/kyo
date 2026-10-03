import XCTest

@MainActor
final class ScheduleEventDetailUITests: XCTestCase {
    func testTappingATimedRowOpensItsDetailsAndDoneClosesThem() throws {
        let app = launchApp()

        let row = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Design review, Work calendar")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()

        let title = app.descendants(matching: .any)["event-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Design review")
        XCTAssertTrue(app.descendants(matching: .any)["event-detail-time"].label.contains("10:00"))

        app.buttons["event-detail-done"].tap()
        XCTAssertTrue(waitForDisappearance(of: title))
        XCTAssertTrue(row.exists)
    }

    func testTappingTheAllDayLineListsTheEventsAndChoosingOneShowsItsDetails() throws {
        let app = launchApp()

        let allDay = app.buttons["schedule-all-day"]
        XCTAssertTrue(allDay.waitForExistence(timeout: 3))
        allDay.tap()

        // Two all-day events, so a list comes first and no details yet.
        let birthday = app.buttons["Sam's birthday, Personal calendar"]
        XCTAssertTrue(birthday.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Holiday, Personal calendar"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["event-detail-title"].exists)

        birthday.tap()

        let title = app.descendants(matching: .any)["event-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Sam's birthday")

        // Done returns to the list, and the list's Done returns to Today.
        app.buttons["event-detail-done"].tap()
        XCTAssertTrue(waitForDisappearance(of: title))
        XCTAssertTrue(birthday.waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForDisappearance(of: birthday))
    }

    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: 3) == .completed
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_FAKE_CALENDAR"] = "full"
        app.launch()
        return app
    }
}
