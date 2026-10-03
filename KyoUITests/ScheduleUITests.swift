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

    func testStatesWithoutReadAccessShowNoScheduleSectionYet() throws {
        for state in ["denied", "restricted", "writeOnly"] {
            let app = launchApp(calendar: state)

            XCTAssertTrue(app.staticTexts["Tasks"].waitForExistence(timeout: 3), state)
            XCTAssertFalse(app.staticTexts["See today's events"].exists, state)
            XCTAssertFalse(app.staticTexts["Nothing scheduled"].exists, state)
            XCTAssertFalse(app.buttons["Connect"].exists, state)
            app.terminate()
        }
    }

    private func launchApp(calendar: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_FAKE_CALENDAR"] = calendar
        app.launch()
        return app
    }
}
