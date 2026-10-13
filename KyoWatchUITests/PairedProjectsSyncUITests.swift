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
        waitForDelivery(group, label: "Original \(token), 0 of 1 done", in: app)
        XCTAssertEqual(group.value as? String, "expanded")
        let task = taskButton(in: app)
        reveal(task, in: app)
        XCTAssertEqual(task.label, "Task \(token)")
        XCTAssertEqual(task.value as? String, "Not completed")
        reveal(group, in: app, upward: false)
        group.tap()
        XCTAssertEqual(group.value as? String, "collapsed")
        app.terminate()
        app.launch()
        reveal(group, in: app)
        XCTAssertEqual(group.value as? String, "collapsed")
        XCTAssertEqual(group.label, "Original \(token), 0 of 1 done")
        group.tap()
        reveal(task, in: app)
        XCTAssertEqual(task.label, "Task \(token)")
    }

    func testWatchObserveRenameAndComplete() throws {
        let token = try requirePhase("watch-command")
        let app = XCUIApplication()
        app.launch()
        let group = projectGroup(in: app)
        waitForDelivery(group, label: "Renamed \(token), 0 of 1 done", in: app)
        XCTAssertEqual(group.value as? String, "expanded")
        let task = taskButton(in: app)
        reveal(task, in: app)
        XCTAssertEqual(task.label, "Task \(token)")
        XCTAssertEqual(task.value as? String, "Not completed")
        task.tap()
        XCTAssertEqual(task.value as? String, "Completed")
        reveal(group, in: app, upward: false)
        XCTAssertEqual(group.label, "Renamed \(token), 1 of 1 done")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "paired-projects-watch-renamed-completed"
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
            app.swipeDown()
        }
        XCTFail("Project catalog must arrive through actual WatchConnectivity: \(label)")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<8 where !element.isHittable {
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
    }
}
