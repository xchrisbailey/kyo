import XCTest

@MainActor
final class PairedProjectsSyncUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testWatchObserveOriginal() throws {
        let token = try requirePhase("watch-original")
        let app = XCUIApplication()
        app.launch()
        let everyday = app.staticTexts["tasks-empty"]
        reveal(everyday, in: app)
        XCTAssertEqual(everyday.label, "No tasks yet")
        let group = projectGroup(in: app)
        waitForDelivery(group, label: "Original \(token), 0 of 2 done", in: app)
        XCTAssertEqual(group.value as? String, "expanded")
        let task = taskButton(in: app)
        reveal(task, in: app)
        XCTAssertEqual(task.label, "Task \(token)")
        XCTAssertEqual(task.value as? String, "Not completed")
        reveal(group, in: app, upward: false)
        capture("paired-watch-project-expanded", in: app)
        group.tap()
        XCTAssertEqual(group.value as? String, "collapsed")
        capture("paired-watch-project-collapsed", in: app)
        app.terminate()
        app.launch()
        reveal(group, in: app)
        XCTAssertEqual(group.value as? String, "collapsed")
        XCTAssertEqual(group.label, "Original \(token), 0 of 2 done")
        group.tap()
        reveal(task, in: app)
        XCTAssertEqual(task.label, "Task \(token)")
    }

    func testWatchObserveRenameAndComplete() throws {
        let token = try requirePhase("watch-command")
        let app = XCUIApplication()
        app.launch()
        let group = projectGroup(in: app)
        waitForDelivery(group, label: "Renamed \(token), 0 of 2 done", in: app)
        XCTAssertEqual(group.value as? String, "expanded")
        let task = taskButton(in: app)
        reveal(task, in: app)
        XCTAssertEqual(task.label, "Task \(token)")
        XCTAssertEqual(task.value as? String, "Not completed")
        let firstID = task.identifier
        let second = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "task-checkbox-", firstID)).firstMatch
        reveal(second, in: app)
        XCTAssertEqual(second.label, "Delete \(token)")
        let secondID = second.identifier
        let first = app.buttons[firstID]
        reveal(first, in: app, upward: false)
        first.tap()
        XCTAssertEqual(first.value as? String, "Completed")
        reveal(group, in: app, upward: false)
        XCTAssertEqual(group.label, "Renamed \(token), 1 of 2 done")
        capture("paired-watch-project-first-completion", in: app)
        reveal(first, in: app)
        first.tap()
        XCTAssertEqual(first.value as? String, "Not completed")
        reveal(group, in: app, upward: false)
        XCTAssertEqual(group.label, "Renamed \(token), 0 of 2 done")
        capture("paired-watch-project-reopened", in: app)
        reveal(first, in: app)
        first.swipeLeft()
        let edit = app.buttons["task-edit-\(String(firstID.dropFirst("task-checkbox-".count)))"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let editor = app.textFields["task-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        capture("paired-watch-project-edit-sheet", in: app)
        editor.tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Task \(token)".count) + "Edited \(token)")
        app.buttons["task-text-save"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.identifier, firstID)
        XCTAssertEqual(first.label, "Edited \(token)")
        capture("paired-watch-project-edited-task", in: app)
        XCTAssertEqual(first.value as? String, "Not completed")
        let removed = app.buttons[secondID]
        reveal(removed, in: app)
        removed.swipeLeft()
        let delete = app.buttons["task-delete-\(String(secondID.dropFirst("task-checkbox-".count)))"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(removed.waitForNonExistence(timeout: 5))
        reveal(group, in: app, upward: false)
        XCTAssertEqual(group.label, "Renamed \(token), 0 of 1 done")
        capture("paired-watch-project-task-deleted", in: app)
        reveal(first, in: app)
        first.tap()
        XCTAssertEqual(first.value as? String, "Completed")
        reveal(group, in: app, upward: false)
        XCTAssertEqual(group.label, "Renamed \(token), 1 of 1 done")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "paired-projects-watch-renamed-completed"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func requirePhase(_ phase: String) throws -> String {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["KYO_PAIRED_PROJECTS"] == "1" && environment["KYO_PAIRED_PROJECTS_PHASE"] == phase)
        return try XCTUnwrap(environment["KYO_PAIRED_PROJECTS_TOKEN"])
    }

    private func projectGroup(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-group-collapse-")).firstMatch
    }

    private func taskButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-")).firstMatch
    }

    private func waitForDelivery(_ element: XCUIElement, label: String, in app: XCUIApplication) {
        reveal(app.buttons["section-header-projects"], in: app)
        // List rows are lazy. Keep drawing the group as new catalog content arrives.
        for _ in 0..<18 {
            reveal(element, in: app)
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
            if XCTWaiter.wait(for: [expectation], timeout: 5) == .completed { return }
            scroll(in: app, upward: false)
        }
        XCTFail("Project catalog must arrive through actual WatchConnectivity: \(label)")
    }

    private func scroll(in app: XCUIApplication, upward: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.6 : 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.4 : 0.6))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<8 where !element.isHittable {
            scroll(in: app, upward: upward)
        }
    }
}
