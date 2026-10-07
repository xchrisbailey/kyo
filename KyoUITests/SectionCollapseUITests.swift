import XCTest

/// Collapsing and expanding the sections on Today. Every launch gets its own collapse state through
/// `KYO_COLLAPSED_SECTIONS_SUITE`; a relaunch reuses the same suite to find what the first one left.
@MainActor
final class SectionCollapseUITests: XCTestCase {
    private let suite = "kyo.collapsed-sections.ui-tests.\(UUID().uuidString)"

    /// M3. Header values and labels, collapsing with and without rows, and the schedule's show-more surviving a collapse.
    func testCollapseBasicsHideRowsKeepSummariesAndLeaveOtherSectionsAlone() throws {
        let app = launchApp(calendar: "full")
        let schedule = app.buttons["section-header-schedule"]
        let tasks = app.buttons["section-header-tasks"]
        let habits = app.buttons["section-header-habits"]
        let memos = app.buttons["section-header-memos"]

        for section in [schedule, tasks, habits, memos] {
            XCTAssertTrue(section.waitForExistence(timeout: 10), section.identifier)
            XCTAssertEqual(section.value as? String, "expanded", section.identifier)
        }
        XCTAssertEqual(tasks.label, "Tasks, For today")
        XCTAssertEqual(habits.label, "Habits, Small steps, daily")

        // Empty sections: collapsing hides their empty-state rows, and the header says what's missing.
        XCTAssertTrue(app.staticTexts["No tasks yet"].exists)
        XCTAssertTrue(app.staticTexts["No habits yet"].exists)
        tasks.tap()
        habits.tap()
        memos.tap()
        XCTAssertTrue(waitForValue("collapsed", of: tasks))
        XCTAssertTrue(waitForValue("collapsed", of: habits))
        XCTAssertTrue(waitForValue("collapsed", of: memos))
        XCTAssertTrue(app.staticTexts["No tasks yet"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No habits yet"].exists)
        XCTAssertFalse(app.staticTexts["Tap + to add a memo"].exists)
        XCTAssertEqual(tasks.label, "Tasks, No tasks")
        XCTAssertEqual(habits.label, "Habits, No habits")

        tasks.tap()
        habits.tap()
        memos.tap()
        XCTAssertTrue(waitForValue("expanded", of: tasks))
        XCTAssertTrue(waitForValue("expanded", of: habits))
        XCTAssertTrue(waitForValue("expanded", of: memos))
        XCTAssertTrue(app.staticTexts["No tasks yet"].waitForExistence(timeout: 10))
        XCTAssertEqual(tasks.label, "Tasks, For today")
        XCTAssertEqual(habits.label, "Habits, Small steps, daily")

        // A section with rows: collapsing hides the rows but not its header or the summary stats, and
        // touches no other section. The header's label carries the collapsed summary.
        addTask("Water the plants", to: app)
        tasks.tap()
        XCTAssertTrue(waitForValue("collapsed", of: tasks))
        XCTAssertTrue(app.buttons["Water the plants"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(tasks.exists)
        XCTAssertEqual(tasks.label, "Tasks, 0 of 1 done")
        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].exists)
        XCTAssertEqual(habits.value as? String, "expanded")
        XCTAssertEqual(memos.value as? String, "expanded")
        XCTAssertEqual(schedule.value as? String, "expanded")
        XCTAssertTrue(app.descendants(matching: .any)["task-count-summary"].exists, "the summary stats don't collapse")

        tasks.tap()
        XCTAssertTrue(waitForValue("expanded", of: tasks))
        XCTAssertTrue(app.buttons["Water the plants"].waitForExistence(timeout: 10))
        XCTAssertEqual(tasks.label, "Tasks, For today")

        // Collapse and show-more are separate states: collapsing the schedule keeps it showing more.
        let more = app.buttons["schedule-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        XCTAssertTrue(app.buttons["schedule-show-less"].waitForExistence(timeout: 10))

        schedule.tap()
        XCTAssertTrue(waitForValue("collapsed", of: schedule))
        XCTAssertTrue(app.buttons["schedule-show-less"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["schedule-all-day"].exists)

        schedule.tap()
        XCTAssertTrue(waitForValue("expanded", of: schedule))
        XCTAssertTrue(app.buttons["schedule-show-less"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["schedule-more"].exists)
    }

    /// M4. A collapsed Memos header keeps See all, and neither opening the sheet nor saving a memo expands it.
    func testACollapsedMemosSectionStaysCollapsedThroughSeeAllAndSavingAMemo() throws {
        let app = launchApp()
        addMemo("Weekend idea", to: app)
        let memos = app.buttons["section-header-memos"]
        memos.tap()
        XCTAssertTrue(waitForValue("collapsed", of: memos))
        XCTAssertEqual(memos.label, "Memos, 1 memo")

        let seeAll = app.buttons["See all"]
        XCTAssertTrue(seeAll.exists)
        seeAll.tap()

        XCTAssertTrue(app.navigationBars["Memos"].waitForExistence(timeout: 10))
        app.navigationBars["Memos"].buttons.firstMatch.tap()
        XCTAssertTrue(memos.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Memos"].waitForNonExistence(timeout: 10))
        XCTAssertEqual(memos.value as? String, "collapsed")

        addMemo("Quiet capture", to: app, expectingRow: false)

        let relabelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Memos, 2 memos"), object: memos)
        XCTAssertEqual(XCTWaiter.wait(for: [relabelled], timeout: 10), .completed)
        XCTAssertEqual(memos.value as? String, "collapsed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo.'")).firstMatch.exists)
    }

    /// M5. Starting a task draft expands a collapsed Tasks section; collapsing mid-draft keeps the text, and
    /// starting a task again brings the draft back focused.
    func testTaskDraftExpandsTasksAndSurvivesCollapsingMidDraft() throws {
        let app = launchApp()
        let tasks = app.buttons["section-header-tasks"]
        tasks.tap()
        XCTAssertTrue(waitForValue("collapsed", of: tasks))

        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue("expanded", of: tasks))
        field.typeText("Half-written")

        tasks.tap()

        XCTAssertTrue(waitForValue("collapsed", of: tasks))
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "the keyboard doesn't stay up over a hidden field"
        )

        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()

        XCTAssertTrue(waitForValue("expanded", of: tasks))
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Half-written")
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)],
                timeout: 10
            ) == .completed,
            "the draft is focused again"
        )
        field.typeText(" and done\n")
        XCTAssertTrue(app.buttons["Half-written and done"].waitForExistence(timeout: 10))
        XCTAssertEqual(tasks.value as? String, "expanded", "it stays expanded after the task is added")
    }

    func testCollapsedSectionsSurviveARelaunch() throws {
        let app = launchApp()
        app.buttons["section-header-habits"].tap()
        app.buttons["section-header-tasks"].tap()
        XCTAssertTrue(waitForValue("collapsed", of: app.buttons["section-header-habits"]))
        XCTAssertTrue(waitForValue("collapsed", of: app.buttons["section-header-tasks"]))
        relaunch(app)

        XCTAssertTrue(waitForValue("collapsed", of: app.buttons["section-header-habits"]))
        XCTAssertEqual(app.buttons["section-header-tasks"].value as? String, "collapsed")
        XCTAssertEqual(app.buttons["section-header-memos"].value as? String, "expanded")
        XCTAssertFalse(app.staticTexts["No habits yet"].exists)
    }

    // MARK: Helpers

    private func launchApp(calendar: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_COLLAPSED_SECTIONS_SUITE"] = suite
        if let calendar { app.launchEnvironment["KYO_FAKE_CALENDAR"] = calendar }
        app.launch()
        return app
    }

    /// Generous: a collapse or expansion is an animation plus a re-render, and the CI runner is slow enough that
    /// a relaunched app can take several seconds before its elements are queryable.
    private func waitForValue(_ value: String, of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Terminates the app, waits for the process to be gone, then launches it again with the same launch environment.
    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app is still running after terminate")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "the app isn't in the foreground after launch")
    }

    private func addTask(_ title: String, to app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(title + "\n")
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10))
    }

    private func addMemo(_ text: String, to app: XCUIApplication, expectingRow: Bool = true) {
        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        compose.typeText(text)
        app.buttons["Save"].tap()
        if expectingRow {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. \(text).'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
        }
    }
}
