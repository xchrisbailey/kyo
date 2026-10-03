import XCTest

@MainActor
final class ScheduleUITests: XCTestCase {
    func testConnectShowsTheSeededAllDayLineAndTimedRows() throws {
        let app = launchApp(calendar: "notDetermined")

        XCTAssertTrue(app.staticTexts["See today's events"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Calendar"].exists)
        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.exists)
        connect.tap()

        XCTAssertTrue(app.staticTexts["5 events"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["See today's events"].exists)
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
    }

    func testSeededEventsShowWithoutConnecting() throws {
        let app = launchApp(calendar: "full")

        XCTAssertTrue(app.staticTexts["5 events"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Connect"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["schedule-all-day"].exists)
    }

    func testExpandingShowsTheEndedEventAndShowLessCollapsesAgain() throws {
        let app = launchApp(calendar: "full")
        let more = app.buttons["schedule-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        XCTAssertEqual(more.label, "1 more event")
        XCTAssertFalse(app.buttons["schedule-show-less"].exists)

        more.tap()

        let standup = row(app, endingWith: "Standup, Work calendar, ended")
        XCTAssertTrue(standup.waitForExistence(timeout: 3))
        XCTAssertTrue(standup.label.contains("9:30"), standup.label)
        XCTAssertTrue(row(app, endingWith: "Design review, Work calendar").exists)
        XCTAssertTrue(row(app, endingWith: "Lunch, Personal calendar").exists)
        XCTAssertFalse(more.exists)
        let showLess = app.buttons["schedule-show-less"]
        XCTAssertTrue(showLess.exists)
        // In time order.
        XCTAssertLessThan(standup.frame.minY, row(app, endingWith: "Design review, Work calendar").frame.minY)

        showLess.tap()

        XCTAssertTrue(app.buttons["schedule-more"].waitForExistence(timeout: 3))
        XCTAssertFalse(row(app, endingWith: "Standup, Work calendar, ended").exists)
        XCTAssertFalse(app.buttons["schedule-show-less"].exists)
    }

    func testTheExpandedStateIsNotRememberedAcrossLaunches() throws {
        let app = launchApp(calendar: "full")
        let more = app.buttons["schedule-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        XCTAssertTrue(app.buttons["schedule-show-less"].waitForExistence(timeout: 3))
        app.terminate()

        app.launch()

        XCTAssertTrue(app.buttons["schedule-more"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["schedule-show-less"].exists)
    }

    func testAnEmptyDayShowsNothingScheduled() throws {
        let app = launchApp(calendar: "empty")

        XCTAssertTrue(app.staticTexts["Nothing scheduled"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Calendar"].exists)
        // The summary stats are unchanged.
        XCTAssertTrue(app.descendants(matching: .any)["task-count-summary"].exists)
    }

    func testDeniedAndWriteOnlyAccessShowTheAccessOffLineWithOpenSettings() throws {
        for state in ["denied", "writeOnly"] {
            let app = launchApp(calendar: state)

            XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 3), state)
            XCTAssertTrue(app.staticTexts["Schedule"].exists, state)
            XCTAssertFalse(app.buttons["Connect"].exists, state)
            XCTAssertFalse(app.staticTexts["Nothing scheduled"].exists, state)
            XCTAssertTrue(app.buttons["Hide schedule"].exists, state)

            // The fake records the request instead of leaving Kyo for the Settings app.
            let openSettings = app.buttons["Open Settings"]
            XCTAssertTrue(openSettings.exists, state)
            XCTAssertEqual(openSettings.value as? String ?? "", "", state)
            openSettings.tap()
            XCTAssertEqual(openSettings.value as? String, "Requested", state)
            XCTAssertEqual(app.state, .runningForeground, state)
            app.terminate()
        }
    }

    func testRestrictedAccessShowsTheUnavailableLineWithoutAButton() throws {
        let app = launchApp(calendar: "restricted")

        XCTAssertTrue(app.staticTexts["Calendar access isn't available"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Open Settings"].exists)
        XCTAssertFalse(app.buttons["Connect"].exists)
        XCTAssertTrue(app.buttons["Hide schedule"].exists)
    }

    func testDismissingEachPromptLineHidesTheSchedule() throws {
        let lines = [
            ("notDetermined", "See today's events"),
            ("denied", "Calendar access is off"),
            ("restricted", "Calendar access isn't available"),
        ]
        for (state, line) in lines {
            let app = launchApp(calendar: state)
            XCTAssertTrue(app.staticTexts[line].waitForExistence(timeout: 3), state)

            app.buttons["Hide schedule"].tap()

            XCTAssertFalse(app.staticTexts[line].exists, state)
            XCTAssertFalse(app.staticTexts["Schedule"].exists, state)
            XCTAssertTrue(app.staticTexts["Tasks"].exists, state)
            app.terminate()
        }
    }

    func testTurningShowScheduleBackOnFromSettingsShowsTheCurrentAccessState() throws {
        let app = launchApp(calendar: "denied")
        XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 3))
        app.buttons["Hide schedule"].tap()
        XCTAssertFalse(app.staticTexts["Calendar access is off"].exists)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let showSchedule = app.switches["Show schedule"]
        XCTAssertTrue(showSchedule.waitForExistence(timeout: 3))
        XCTAssertEqual(showSchedule.value as? String, "0")
        showSchedule.switches.firstMatch.tap()
        XCTAssertEqual(showSchedule.value as? String, "1")
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Schedule"].exists)
    }

    func testShowScheduleIsOnByDefaultAndTurningItOffFromSettingsHidesTheSection() throws {
        let app = launchApp(calendar: "full")
        XCTAssertTrue(app.staticTexts["5 events"].waitForExistence(timeout: 3))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let showSchedule = app.switches["Show schedule"]
        XCTAssertTrue(showSchedule.waitForExistence(timeout: 3))
        XCTAssertEqual(showSchedule.value as? String, "1")
        showSchedule.switches.firstMatch.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Tasks"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["5 events"].exists)
        XCTAssertFalse(app.staticTexts["Schedule"].exists)
    }

    private func row(_ app: XCUIApplication, endingWith suffix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", suffix)).firstMatch
    }

    private func launchApp(calendar: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_FAKE_CALENDAR"] = calendar
        app.launch()
        return app
    }
}
