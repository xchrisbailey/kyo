import XCTest

/// The Schedule section on Today: the happy path from Connect to showing more and less, and the
/// denied-access flow through Open Settings, the Calendars screen, Hide schedule and Show schedule.
@MainActor
final class ScheduleUITests: XCTestCase {
    func testConnectShowsTheScheduleAndShowMoreAndShowLessSwitchTheCompactList() throws {
        let app = launchApp(calendar: "notDetermined")

        XCTAssertTrue(app.staticTexts["See today's events"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Schedule, Calendar"].exists)
        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.exists)
        connect.tap()

        XCTAssertTrue(app.buttons["Schedule, 5 events"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["See today's events"]))
        XCTAssertFalse(app.buttons["Connect"].exists)

        let allDay = app.descendants(matching: .any)["schedule-all-day"]
        XCTAssertTrue(allDay.exists)
        XCTAssertEqual(allDay.label, "All day: Holiday, Sam's birthday")

        // The fake calendar pins the clock to 10:30: Standup has ended, Design review is running.
        let nowRow = row(app, endingWith: "Design review, Work calendar")
        let lunch = row(app, endingWith: "Lunch, Personal calendar")
        XCTAssertTrue(nowRow.exists)
        XCTAssertTrue(nowRow.label.hasPrefix("Now, "), nowRow.label)
        XCTAssertTrue(lunch.exists)
        XCTAssertLessThan(nowRow.frame.minY, lunch.frame.minY)
        XCTAssertFalse(row(app, endingWith: "Standup, Work calendar, ended").exists)

        let more = app.buttons["schedule-more"]
        XCTAssertTrue(more.exists)
        XCTAssertEqual(more.label, "1 more event")
        XCTAssertFalse(app.buttons["schedule-show-less"].exists)

        more.tap()

        let standup = row(app, endingWith: "Standup, Work calendar, ended")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        XCTAssertTrue(standup.label.contains("9:30"), standup.label)
        XCTAssertTrue(nowRow.exists)
        XCTAssertTrue(lunch.exists)
        XCTAssertTrue(waitForDisappearance(of: more))
        let showLess = app.buttons["schedule-show-less"]
        XCTAssertTrue(showLess.exists)
        // In time order.
        XCTAssertLessThan(standup.frame.minY, nowRow.frame.minY)

        showLess.tap()

        XCTAssertTrue(app.buttons["schedule-more"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForDisappearance(of: row(app, endingWith: "Standup, Work calendar, ended")))
        XCTAssertFalse(app.buttons["schedule-show-less"].exists)
    }

    func testDeniedAccessOpenSettingsCalendarsHideScheduleAndShowScheduleFromSettings() throws {
        let app = launchApp(calendar: "denied")

        XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["section-header-schedule"].exists)
        XCTAssertFalse(app.buttons["Connect"].exists)
        XCTAssertFalse(app.staticTexts["Nothing scheduled"].exists)
        XCTAssertTrue(app.buttons["Hide schedule"].exists)

        // The fake records the request instead of leaving Kyo for the Settings app.
        let openSettings = app.buttons["Open Settings"]
        XCTAssertTrue(openSettings.exists)
        XCTAssertEqual(openSettings.value as? String ?? "", "")
        openSettings.tap()
        XCTAssertTrue(waitForValue("Requested", of: openSettings))
        XCTAssertEqual(app.state, .runningForeground)

        // Without full access the Calendars screen shows the access line instead of calendars.
        openCalendars(in: app)
        XCTAssertTrue(app.buttons["schedule-open-settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["schedule-calendar-work"].exists)
        XCTAssertFalse(app.staticTexts["iCloud"].exists)
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Show schedule"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        let hide = app.buttons["Hide schedule"]
        XCTAssertTrue(hide.waitForExistence(timeout: 10))
        hide.tap()

        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["Calendar access is off"]))
        XCTAssertTrue(waitForDisappearance(of: app.buttons["section-header-schedule"]))
        XCTAssertTrue(app.buttons["section-header-tasks"].exists)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let showSchedule = app.switches["Show schedule"]
        XCTAssertTrue(showSchedule.waitForExistence(timeout: 10))
        XCTAssertEqual(showSchedule.value as? String, "0")
        showSchedule.switches.firstMatch.tap()
        XCTAssertTrue(waitForValue("1", of: showSchedule))
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["section-header-schedule"].exists)
    }

    private func row(_ app: XCUIApplication, endingWith suffix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", suffix)).firstMatch
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
