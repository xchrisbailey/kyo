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

        // In time order, each as one element: "<time>, <title>, <calendar> calendar".
        let rows = ["Standup, Work calendar", "Design review, Work calendar", "Lunch, Personal calendar"]
        let labels = rows.map { suffix in
            app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", suffix)).firstMatch
        }
        for row in labels { XCTAssertTrue(row.exists) }
        XCTAssertLessThan(labels[0].frame.minY, labels[1].frame.minY)
        XCTAssertLessThan(labels[1].frame.minY, labels[2].frame.minY)
        XCTAssertTrue(labels[1].label.contains("10:00"), labels[1].label)
    }

    func testSeededEventsShowWithoutConnecting() throws {
        let app = launchApp(calendar: "full")

        XCTAssertTrue(app.staticTexts["5 events"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Connect"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["schedule-all-day"].exists)
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

    private func launchApp(calendar: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_FAKE_CALENDAR"] = calendar
        app.launch()
        return app
    }
}
