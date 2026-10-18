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

    func testWatchObserveProjectsDisabled() throws {
        let token = try requirePhase("watch-off")
        let app = XCUIApplication()
        app.launch()
        let header = app.buttons["section-header-tasks"]
        reveal(header, in: app, upward: false)
        XCTAssertTrue(header.isHittable)
        if header.value as? String == "expanded" { header.tap() }
        let delivery = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Tasks, 0 of 2 done"), object: header)
        XCTAssertEqual(XCTWaiter.wait(for: [delivery], timeout: 90), .completed,
            "the phone's off preference must move both tasks into Tasks")
        capture("paired-watch-projects-disabled-logical-count", in: app)
        header.tap()
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "expanded"), object: header)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        XCTAssertEqual(header.value as? String, "expanded")
        capture("paired-watch-projects-disabled-expanded-tasks", in: app)
        assertBothTasks(token: token, in: app)
        // Watch List materializes rows as they enter the viewport. Scan the section locations
        // rather than treating an offscreen row's absence from one snapshot as lost content.
        for _ in 0..<5 {
            XCTAssertFalse(app.buttons["section-header-projects"].exists)
            XCTAssertFalse(projectGroup(in: app).exists)
            scroll(in: app, upward: true)
        }
        capture("paired-watch-projects-disabled-tasks-retained", in: app)
    }

    func testWatchObserveProjectsEnabledAgain() throws {
        let token = try requirePhase("watch-on")
        let app = XCUIApplication()
        app.launch()
        waitForDelivery(projectGroup(in: app), label: "Original \(token), 0 of 2 done", in: app)
        assertBothTasks(token: token, in: app)
        capture("paired-watch-projects-reenabled", in: app)
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
        let keyboardEditor = app.textViews.firstMatch
        XCTAssertTrue(keyboardEditor.waitForExistence(timeout: 5))
        XCTAssertEqual(keyboardEditor.value as? String, "Task \(token)")
        capture("paired-watch-project-native-keyboard", in: app)
        keyboardEditor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Task \(token)".count) + "Edited \(token)")
        XCTAssertEqual(keyboardEditor.value as? String, "Edited \(token)")
        app.buttons["Done"].tap() // label-query: native Watch keyboard has no app-owned identifier
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.identifier, firstID)
        XCTAssertEqual(first.label, "Edited \(token)")
        capture("paired-watch-project-edited-task", in: app)
        XCTAssertEqual(first.value as? String, "Not completed")
        reveal(group, in: app, upward: false)
        XCTAssertEqual(group.label, "Renamed \(token), 0 of 2 done")
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

    private func assertBothTasks(token: String, in app: XCUIApplication) {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
            "task-checkbox-", "Task \(token)")).firstMatch // label-query: discovers the seeded task whose exact text is under test
        reveal(first, in: app, upward: false)
        if !first.exists || !first.isHittable { reveal(first, in: app) }
        if !first.exists || !first.isHittable { recordProjectControls(in: app) }
        XCTAssertTrue(first.isHittable)
        XCTAssertEqual(first.label, "Task \(token)")
        XCTAssertEqual(first.value as? String, "Not completed")
        let firstID = first.identifier
        let second = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
            "task-checkbox-", "Delete \(token)")).firstMatch // label-query: discovers the second seeded task whose text must remain available
        reveal(second, in: app)
        if !second.exists || !second.isHittable { recordProjectControls(in: app) }
        XCTAssertTrue(second.isHittable)
        XCTAssertEqual(second.label, "Delete \(token)")
        XCTAssertEqual(second.value as? String, "Not completed")
        XCTAssertNotEqual(second.identifier, firstID, "both original tasks remain independently actionable")
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
        let deliveredGroup = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "project-group-collapse-")
        ).firstMatch
        let deadline = Date.now.addingTimeInterval(90)
        var upward = true
        var steps = 0
        // Delivery and the button's accessibility are separate observable requirements.
        while Date.now < deadline {
            if deliveredGroup.exists && deliveredGroup.label == label {
                recordProjectControls(in: app)
                XCTAssertTrue(element.exists, "Delivered project group must expose a button accessibility trait")
                reveal(element, in: app)
                XCTAssertTrue(element.isHittable, "Delivered project group button must be tappable")
                XCTAssertEqual(element.label, label)
                return
            }
            scroll(in: app, upward: upward)
            steps += 1
            if steps == 8 {
                upward.toggle()
                steps = 0
            }
        }
        recordProjectControls(in: app)
        XCTFail("Project catalog must arrive through actual WatchConnectivity: \(label)")
    }

    private func recordProjectControls(in app: XCUIApplication) {
        let controls = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier == %@",
            "project-group-collapse-", "task-checkbox-", "plus"
        ))
        retainUIDiagnostics("paired-watch-project-controls", in: app, candidates: controls)
    }

    private func scroll(in app: XCUIApplication, upward: Bool) {
        let bounds = app.frame
        let captureButton = app.buttons["plus"]
        let bottom = captureButton.exists ? captureButton.frame.minY : bounds.maxY
        // Begin inside the list, above the fixed capture control observed on Watch.
        let lowerY = bottom - 20
        let upperY = max(bounds.minY + 20, lowerY - (bottom - bounds.minY) * 0.3)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let lower = origin.withOffset(CGVector(dx: bounds.width * 0.5, dy: lowerY - bounds.minY))
        let upper = origin.withOffset(CGVector(dx: bounds.width * 0.5, dy: upperY - bounds.minY))
        let start = upward ? lower : upper
        let end = upward ? upper : lower
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            scroll(in: app, upward: upward)
        }
    }
}
