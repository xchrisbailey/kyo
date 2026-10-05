import XCTest

@MainActor
final class ScheduleCalendarsUITests: XCTestCase {
    func testUncheckingACalendarHidesItsEventsFromToday() throws {
        let app = launchApp(calendar: "full")
        XCTAssertTrue(app.staticTexts["5 events"].waitForExistence(timeout: 3))
        let workRows = NSPredicate(format: "label ENDSWITH %@", "Work calendar")
        // With the clock pinned to 10:30 the compact list leaves out the ended Standup.
        XCTAssertEqual(app.descendants(matching: .any).matching(workRows).count, 1)

        openCalendars(in: app)

        // Grouped by account, all checked by default.
        XCTAssertTrue(app.staticTexts["iCloud"].exists)
        XCTAssertTrue(app.staticTexts["Subscribed"].exists)
        let work = app.buttons["schedule-calendar-work"]
        XCTAssertTrue(work.waitForExistence(timeout: 3))
        for id in ["work", "personal", "holidays"] {
            XCTAssertEqual(app.buttons["schedule-calendar-\(id)"].value as? String, "Shown", id)
        }

        work.tap()
        XCTAssertEqual(work.value as? String, "Hidden")
        XCTAssertEqual(app.buttons["schedule-calendar-personal"].value as? String, "Shown")

        app.navigationBars.buttons["Settings"].tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["3 events"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any).matching(workRows).count, 0)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", "Personal calendar")).firstMatch.exists)
    }

    func testUncheckingTheHolidaysCalendarRemovesTheHolidayFromTheAllDayLine() throws {
        let app = launchApp(calendar: "full")
        let allDay = app.descendants(matching: .any)["schedule-all-day"]
        XCTAssertTrue(allDay.waitForExistence(timeout: 3))
        XCTAssertEqual(allDay.label, "All day: Holiday, Sam's birthday")

        openCalendars(in: app)
        app.buttons["schedule-calendar-holidays"].tap()
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["4 events"].waitForExistence(timeout: 3))
        XCTAssertEqual(allDay.label, "All day: Sam's birthday")
    }

    func testTheCalendarsRowIsDisabledWhileShowScheduleIsOff() throws {
        let app = launchApp(calendar: "full")
        XCTAssertTrue(app.staticTexts["5 events"].waitForExistence(timeout: 3))
        app.buttons["Settings"].tap()
        let showSchedule = app.switches["Show schedule"]
        XCTAssertTrue(showSchedule.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Calendars"].isEnabled)

        showSchedule.switches.firstMatch.tap()

        XCTAssertFalse(app.buttons["Calendars"].isEnabled)
    }

    func testWithoutFullAccessTheCalendarsScreenShowsTheAccessLine() throws {
        let app = launchApp(calendar: "denied")
        XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 3))

        openCalendars(in: app)

        XCTAssertTrue(app.buttons["schedule-open-settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["schedule-calendar-work"].exists)
        XCTAssertFalse(app.staticTexts["iCloud"].exists)
    }

    private func openCalendars(in app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let calendars = app.buttons["Calendars"]
        XCTAssertTrue(calendars.waitForExistence(timeout: 3))
        calendars.tap()
        XCTAssertTrue(app.navigationBars["Calendars"].waitForExistence(timeout: 3))
    }

    private func launchApp(calendar: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_FAKE_CALENDAR"] = calendar
        app.launch()
        return app
    }
}
