import XCTest

@MainActor
final class WatchSyncSmokeUITests: XCTestCase {
    /// Exercises real phone-to-Watch delivery through WatchConnectivity against the actual,
    /// non-isolated task store. Opt-in only: it needs a paired Watch to receive anything, so
    /// ordinary runs (with no paired simulator or device) skip it rather than hang waiting on
    /// delivery that never arrives. See docs/development.md for the paired-simulator setup
    /// and docs/adr/0001-phone-authoritative-task-snapshots.md for the sync model.
    func testAddCompleteEditAndDeletePropagateToPhoneSideList() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KYO_WATCH_SYNC_SMOKE"] == "1")

        let app = XCUIApplication()
        app.launch() // No KYO_IN_MEMORY_STORE: uses the real, synchronized store.

        let runID = String(UUID().uuidString.prefix(8))
        let titleA = "Sync A \(runID)"
        let titleB = "Sync B \(runID)"
        let titleC = "Sync C \(runID)"
        addTask(titleA, to: app)
        addTask(titleB, to: app)
        addTask(titleC, to: app)

        app.buttons[titleB].tap()
        assertCheckboxValue(app.buttons[titleB], equals: "Completed")

        app.buttons["Edit task: \(titleC)"].tap()
        let editor = app.textFields["task-editor:\(titleC)"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText(" edited\n")
        let editedTitleC = "\(titleC) edited"
        XCTAssertTrue(app.buttons[editedTitleC].waitForExistence(timeout: 3))

        deleteTask(titleA, from: app)

        // Phone-side result the Watch should now match: C active with the edited text,
        // B completed, A gone.
        assertCheckboxValue(app.buttons[editedTitleC], equals: "Not completed")
        assertCheckboxValue(app.buttons[titleB], equals: "Completed")
        XCTAssertFalse(app.buttons[titleA].exists)

        // Clean up B and C so repeated runs don't accumulate tasks in the real, shared store.
        deleteTask(titleB, from: app)
        deleteTask(editedTitleC, from: app)
    }

    /// The phone half of a Watch habit check-off (ADR 0003). An iOS UI test can't drive the
    /// Watch, so the phone adds a habit through the real, synchronized store and waits for the
    /// Watch's set check-off command to arrive; the paired Watch, running the same build, must
    /// have its habit row tapped (by hand, or by the Watch UI automation of the paired-simulator
    /// setup) within `KYO_WATCH_HABIT_TIMEOUT` seconds (default 120). It then expects the
    /// uncheck from a second tap.
    func testWatchHabitCheckOffAndUncheckReachThePhone() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KYO_WATCH_SYNC_SMOKE"] == "1")
        let timeout = TimeInterval(ProcessInfo.processInfo.environment["KYO_WATCH_HABIT_TIMEOUT"] ?? "") ?? 120

        let app = XCUIApplication()
        app.launch() // No KYO_IN_MEMORY_STORE: uses the real, synchronized store.

        let name = "Sync Habit \(String(UUID().uuidString.prefix(8)))"
        app.buttons["Add an item"].tap()
        app.buttons["Habit"].tap()
        let field = app.textFields["Habit name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(name)
        app.buttons["Save"].tap()
        let circle = app.buttons[name]
        XCTAssertTrue(circle.waitForExistence(timeout: 3))
        assertCheckboxValue(circle, equals: "Not completed")

        // Tap the habit row on the Watch: the phone records Today's check-off.
        waitForValue(of: app.buttons[name], matching: "value BEGINSWITH 'Completed'", timeout: timeout,
                     message: "Tap the habit \"\(name)\" on the paired Watch to check it off")
        // Tap it again: the phone removes the check-off.
        waitForValue(of: app.buttons[name], matching: "value == 'Not completed'", timeout: timeout,
                     message: "Tap the habit \"\(name)\" on the paired Watch again to uncheck it")

        // Clean up so repeated runs don't accumulate habits in the real, shared store.
        app.buttons["Edit habit: \(name)"].tap()
        let deleteButton = app.buttons["Delete habit"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()
        app.buttons["Delete habit and log"].tap()
        XCTAssertFalse(app.buttons[name].waitForExistence(timeout: 2))
    }

    private func waitForValue(of element: XCUIElement, matching format: String, timeout: TimeInterval, message: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
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

    private func deleteTask(_ title: String, from app: XCUIApplication) {
        app.buttons["Edit task: \(title)"].swipeLeft()
        let deleteButton = app.buttons["Delete task: \(title)"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()
        let deletedTaskControls = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title))
        let deletionExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: deletedTaskControls
        )
        XCTAssertEqual(XCTWaiter.wait(for: [deletionExpectation], timeout: 3), .completed)
    }

    private func assertCheckboxValue(_ checkbox: XCUIElement, equals expectedValue: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedValue),
            object: checkbox
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }
}
