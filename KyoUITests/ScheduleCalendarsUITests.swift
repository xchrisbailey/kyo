import XCTest

/// Settings → Schedule: the Calendars screen and the Show schedule switch, wired to what Today shows.
@MainActor
final class ScheduleCalendarsUITests: XCTestCase {
    func testHidingCalendarsFiltersTodayAndTurningShowScheduleOffDisablesCalendarsAndHidesTheSection() throws {
        let app = launchApp(calendar: "full")
        XCTAssertTrue(app.buttons["Schedule, 5 events"].waitForExistence(timeout: 10))
        let workRows = NSPredicate(format: "label ENDSWITH %@", "Work calendar")
        // With the clock pinned to 10:30 the compact list leaves out the ended Standup.
        XCTAssertEqual(app.descendants(matching: .any).matching(workRows).count, 1)
        let allDay = app.descendants(matching: .any)["schedule-all-day"]
        XCTAssertTrue(allDay.exists)
        XCTAssertEqual(allDay.label, "All day: Holiday, Sam's birthday")

        openCalendars(in: app)

        // Grouped by account, all checked by default.
        XCTAssertTrue(app.staticTexts["iCloud"].exists)
        XCTAssertTrue(app.staticTexts["Subscribed"].exists)
        let work = app.buttons["schedule-calendar-work"]
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        for id in ["work", "personal", "holidays"] {
            XCTAssertEqual(app.buttons["schedule-calendar-\(id)"].value as? String, "Shown", id)
        }

        work.tap()
        XCTAssertTrue(waitForValue("Hidden", of: work))
        XCTAssertEqual(app.buttons["schedule-calendar-personal"].value as? String, "Shown")
        let holidays = app.buttons["schedule-calendar-holidays"]
        holidays.tap()
        XCTAssertTrue(waitForValue("Hidden", of: holidays))
        XCTAssertEqual(app.buttons["schedule-calendar-personal"].value as? String, "Shown")

        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Show schedule"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        // Work (Standup, Design review) and Holidays (Holiday) are gone; Lunch and Sam's birthday stay.
        XCTAssertTrue(app.buttons["Schedule, 2 events"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any).matching(workRows).count, 0)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", "Personal calendar")).firstMatch.exists)
        XCTAssertEqual(allDay.label, "All day: Sam's birthday")

        // Show schedule is on by default; turning it off disables Calendars and hides the section.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let showSchedule = app.switches["Show schedule"]
        XCTAssertTrue(showSchedule.waitForExistence(timeout: 10))
        XCTAssertEqual(showSchedule.value as? String, "1")
        XCTAssertTrue(app.buttons["Calendars"].isEnabled)

        showSchedule.switches.firstMatch.tap()

        XCTAssertTrue(waitForValue("0", of: showSchedule))
        XCTAssertTrue(waitForDisabled(app.buttons["Calendars"]))
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["section-header-tasks"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForDisappearance(of: app.buttons["Schedule, 2 events"]))
        XCTAssertFalse(app.buttons["section-header-schedule"].exists)
    }

    private func openCalendars(in app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let calendars = app.buttons["Calendars"]
        XCTAssertTrue(calendars.waitForExistence(timeout: 10))
        calendars.tap()
        XCTAssertTrue(app.navigationBars["Calendars"].waitForExistence(timeout: 10))
    }

    private func waitForValue(_ value: String, of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForDisabled(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: element)
        return XCTWaiter.wait(for: [disabled], timeout: timeout) == .completed
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    private func launchApp(calendar: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_FAKE_CALENDAR"] = calendar
        app.launch()
        return app
    }
}
