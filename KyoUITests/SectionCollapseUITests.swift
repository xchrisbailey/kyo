import XCTest

/// Collapsing and expanding the sections on Today. Every launch gets its own collapse state through
/// `KYO_COLLAPSED_SECTIONS_SUITE`; a relaunch reuses the same suite to find what the first one left.
@MainActor
final class SectionCollapseUITests: XCTestCase {
    private let suite = "kyo.collapsed-sections.ui-tests.\(UUID().uuidString)"

    func testEverySectionStartsExpandedAndTheHeaderIsAButtonWithAValue() throws {
        let app = launchApp()

        for section in ["schedule", "tasks", "habits", "memos"] {
            let header = app.buttons["section-header-\(section)"]
            XCTAssertTrue(header.waitForExistence(timeout: 3), section)
            XCTAssertEqual(header.value as? String, "expanded", section)
        }
        XCTAssertEqual(app.buttons["section-header-tasks"].label, "Tasks, For today")
    }

    func testTappingAHeaderHidesAndShowsItsRowsWithoutTouchingTheOtherSections() throws {
        let app = launchApp()
        addTask("Water the plants", to: app)
        let tasks = app.buttons["section-header-tasks"]
        XCTAssertTrue(app.buttons["Water the plants"].exists)

        tasks.tap()

        XCTAssertTrue(waitForValue("collapsed", of: tasks))
        XCTAssertFalse(app.buttons["Water the plants"].exists)
        XCTAssertTrue(tasks.exists)
        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].exists)
        XCTAssertEqual(app.buttons["section-header-habits"].value as? String, "expanded")
        XCTAssertEqual(app.buttons["section-header-memos"].value as? String, "expanded")
        XCTAssertTrue(app.descendants(matching: .any)["task-count-summary"].exists, "the summary stats don't collapse")

        tasks.tap()

        XCTAssertTrue(waitForValue("expanded", of: tasks))
        XCTAssertTrue(app.buttons["Water the plants"].waitForExistence(timeout: 3))
    }

    func testCollapsingHidesEmptyStateRows() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["No tasks yet"].exists)
        XCTAssertTrue(app.staticTexts["No habits yet"].exists)

        app.buttons["section-header-tasks"].tap()
        app.buttons["section-header-habits"].tap()
        app.buttons["section-header-memos"].tap()

        XCTAssertFalse(app.staticTexts["No tasks yet"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.staticTexts["No habits yet"].exists)
        XCTAssertFalse(app.staticTexts["Tap + to add a memo"].exists)
    }

    func testSeeAllStaysOnACollapsedMemosHeaderAndOpensTheMemosSheetWithoutToggling() throws {
        let app = launchApp()
        addMemo("Weekend idea", to: app)
        let memos = app.buttons["section-header-memos"]
        memos.tap()
        XCTAssertTrue(waitForValue("collapsed", of: memos))

        let seeAll = app.buttons["See all"]
        XCTAssertTrue(seeAll.exists)
        seeAll.tap()

        XCTAssertTrue(app.navigationBars["Memos"].waitForExistence(timeout: 3))
        app.navigationBars["Memos"].buttons.firstMatch.tap()
        XCTAssertTrue(memos.waitForExistence(timeout: 3))
        XCTAssertEqual(memos.value as? String, "collapsed")
    }

    func testSavingAMemoLeavesACollapsedMemosSectionCollapsed() throws {
        let app = launchApp()
        let memos = app.buttons["section-header-memos"]
        memos.tap()
        XCTAssertTrue(waitForValue("collapsed", of: memos))

        addMemo("Quiet capture", to: app, expectingRow: false)

        XCTAssertTrue(app.buttons["Memos, 1 memo"].waitForExistence(timeout: 3))
        XCTAssertEqual(memos.value as? String, "collapsed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Quiet capture.'")).firstMatch.exists)
    }

    func testStartingATaskDraftExpandsACollapsedTasksSection() throws {
        let app = launchApp()
        let tasks = app.buttons["section-header-tasks"]
        tasks.tap()
        XCTAssertTrue(waitForValue("collapsed", of: tasks))

        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()

        XCTAssertTrue(app.textFields["New task"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue("expanded", of: tasks))
        app.textFields["New task"].typeText("Pack the bag\n")
        XCTAssertTrue(app.buttons["Pack the bag"].waitForExistence(timeout: 3))
        XCTAssertEqual(tasks.value as? String, "expanded", "it stays expanded after the task is added")
    }

    func testCollapsingMidDraftKeepsTheTextAndStartingATaskAgainBringsTheDraftBack() throws {
        let app = launchApp()
        let tasks = app.buttons["section-header-tasks"]
        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Half-written")

        tasks.tap()

        XCTAssertTrue(waitForValue("collapsed", of: tasks))
        XCTAssertFalse(field.exists)
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1), "the keyboard doesn't stay up over a hidden field")

        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()

        XCTAssertTrue(waitForValue("expanded", of: tasks))
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "Half-written")
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)],
                timeout: 3
            ) == .completed,
            "the draft is focused again"
        )
        field.typeText(" and done\n")
        XCTAssertTrue(app.buttons["Half-written and done"].waitForExistence(timeout: 3))
    }

    func testCollapsedSectionsSurviveARelaunchAndATaskDraftsExpansionDoes() throws {
        let app = launchApp()
        app.buttons["section-header-habits"].tap()
        app.buttons["section-header-tasks"].tap()
        XCTAssertTrue(waitForValue("collapsed", of: app.buttons["section-header-habits"]))
        relaunch(app)

        XCTAssertTrue(waitForValue("collapsed", of: app.buttons["section-header-habits"]))
        XCTAssertEqual(app.buttons["section-header-tasks"].value as? String, "collapsed")
        XCTAssertEqual(app.buttons["section-header-memos"].value as? String, "expanded")
        XCTAssertFalse(app.staticTexts["No habits yet"].exists)

        app.buttons["Add an item"].tap()
        app.buttons["Task"].tap()
        XCTAssertTrue(waitForValue("expanded", of: app.buttons["section-header-tasks"]))
        relaunch(app)

        XCTAssertTrue(waitForValue("expanded", of: app.buttons["section-header-tasks"]))
        XCTAssertEqual(app.buttons["section-header-habits"].value as? String, "collapsed")
    }

    func testCollapsedTasksAndHabitsHeadersSummarizeTheEmptyListsAndExpandedOnesKeepTheirNotes() throws {
        let app = launchApp()
        let tasks = app.buttons["section-header-tasks"]
        let habits = app.buttons["section-header-habits"]
        XCTAssertEqual(habits.label, "Habits, Small steps, daily")

        tasks.tap()
        habits.tap()

        XCTAssertTrue(waitForValue("collapsed", of: tasks))
        XCTAssertEqual(tasks.label, "Tasks, No tasks")
        XCTAssertEqual(habits.label, "Habits, No habits")

        tasks.tap()
        habits.tap()

        XCTAssertTrue(waitForValue("expanded", of: tasks))
        XCTAssertEqual(tasks.label, "Tasks, For today")
        XCTAssertEqual(habits.label, "Habits, Small steps, daily")
    }

    func testCollapsedTasksHeaderShowsHowManyTasksAreDone() throws {
        let app = launchApp()
        addTask("Water the plants", to: app)
        addTask("Pack the bag", to: app)
        app.buttons["Water the plants"].tap()
        let tasks = app.buttons["section-header-tasks"]

        tasks.tap()

        XCTAssertTrue(waitForValue("collapsed", of: tasks))
        XCTAssertEqual(tasks.label, "Tasks, 1 of 2 done")
    }

    func testCollapsedHabitsHeaderShowsHowManyHabitsDoneTodayAndWhenNoneAreDue() throws {
        let app = launchApp()
        let calendar = Calendar.current
        let otherDay = calendar.weekdaySymbols[calendar.component(.weekday, from: .now) % 7]
        let habits = app.buttons["section-header-habits"]

        addHabit("Elsewhere", onlyOn: otherDay, to: app)
        habits.tap()
        XCTAssertTrue(waitForValue("collapsed", of: habits))
        XCTAssertEqual(habits.label, "Habits, Nothing due today")

        habits.tap()
        XCTAssertTrue(waitForValue("expanded", of: habits))
        addHabit("Stretch", to: app)
        addHabit("Read", to: app)
        app.buttons["Stretch"].tap()
        habits.tap()

        XCTAssertTrue(waitForValue("collapsed", of: habits))
        XCTAssertEqual(habits.label, "Habits, 1 of 2 done", "the habit on another day isn't counted")
    }

    func testCollapsingTheScheduleKeepsItShowingMore() throws {
        let app = launchApp(calendar: "full")
        let schedule = app.buttons["section-header-schedule"]
        let more = app.buttons["schedule-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        XCTAssertTrue(app.buttons["schedule-show-less"].waitForExistence(timeout: 3))

        schedule.tap()

        XCTAssertTrue(waitForValue("collapsed", of: schedule))
        XCTAssertFalse(app.buttons["schedule-show-less"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["schedule-all-day"].exists)

        schedule.tap()

        XCTAssertTrue(app.buttons["schedule-show-less"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["schedule-more"].exists)
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
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(title + "\n")
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3))
    }

    private func addHabit(_ name: String, onlyOn weekday: String? = nil, to app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(name)
        if let weekday {
            app.buttons["Weekdays"].tap()
            app.buttons[weekday].tap()
        }
        app.buttons["Save"].tap()
        if weekday == nil {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3))
        }
    }

    private func addMemo(_ text: String, to app: XCUIApplication, expectingRow: Bool = true) {
        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 3))
        compose.typeText(text)
        app.buttons["Save"].tap()
        if expectingRow {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. \(text).'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 3))
        }
    }
}
