import XCTest

/// The Simulator controller runs four supported phases; phone receipt needs physical devices.
@MainActor
final class PairedProjectsSyncUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testPhoneSeed() throws {
        let token = try requirePhase("phone-seed")
        let app = XCUIApplication()
        app.launch()
        revealAndTap(app.buttons["section-link-projects"], in: app)
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Original \(token)")
        app.buttons["project-name-save"].tap()
        let project = projectButton(in: app)
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        XCTAssertEqual(project.label, "Original \(token)")
        project.tap()
        app.buttons["project-add-task"].tap()
        let task = app.textFields["project-task-editor"]
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.tap()
        task.typeText("Task \(token)")
        app.buttons["project-task-today"].tap()
        app.buttons["project-task-save"].tap()
        app.buttons["project-add-task"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.tap()
        task.typeText("Delete \(token)")
        app.buttons["project-task-today"].tap()
        app.buttons["project-task-save"].tap()
        app.buttons["projects-done"].tap()
        let checkbox = taskButton(in: app)
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        XCTAssertEqual(checkbox.label, "Task \(token)")
        XCTAssertEqual(checkbox.value as? String, "Not completed")
    }

    func testPhoneRename() throws {
        let token = try requirePhase("phone-rename")
        let app = XCUIApplication()
        app.launch()
        revealAndTap(app.buttons["section-link-projects"], in: app)
        let project = projectButton(in: app)
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        XCTAssertEqual(project.label, "Original \(token)")
        project.tap()
        app.buttons["project-rename"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Original \(token)".count) + "Renamed \(token)")
        app.buttons["project-name-save"].tap()
        app.buttons["projects-done"].tap()
        let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-group-open-")).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10))
        XCTAssertEqual(group.label, "Renamed \(token)")
    }

    func testPhoneVerifyWatchCompletion() throws {
        let token = try requirePhase("phone-verify")
        let app = XCUIApplication()
        app.launch()
        let checkbox = taskButton(in: app)
        XCTAssertTrue(checkbox.waitForExistence(timeout: 15))
        let completion = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Completed"), object: checkbox)
        let receipt = XCTWaiter.wait(for: [completion], timeout: 90)
        if receipt != .completed {
            retainUIDiagnostics("phone-watch-command-receipt", in: app,
                                candidates: app.descendants(matching: .any).matching(identifier: checkbox.identifier))
        }
        XCTAssertEqual(receipt, .completed,
                       "Watch command must reach the authoritative phone store")
        XCTAssertEqual(checkbox.label, "Edited \(token)")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-")).count, 1)
        let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-group-open-")).firstMatch
        XCTAssertEqual(group.label, "Renamed \(token)")
        let id = String(group.identifier.dropFirst("project-group-open-".count))
        XCTAssertEqual(app.staticTexts["project-group-summary-\(id)"].label, "1 of 1 done")
        XCTAssertEqual(app.descendants(matching: .any)["task-count-summary"].value as? String, "1 / 1 tasks done")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "paired-projects-phone-received-watch-command"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func requirePhase(_ phase: String) throws -> String {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["KYO_PAIRED_PROJECTS"] == "1" && environment["KYO_PAIRED_PROJECTS_PHASE"] == phase)
        return try XCTUnwrap(environment["KYO_PAIRED_PROJECTS_TOKEN"])
    }

    private func projectButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
    }

    private func taskButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-")).firstMatch
    }

    private func revealAndTap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable && element.frame.maxY < app.buttons["add-item"].frame.minY {
                element.tap()
                return
            }
            app.swipeUp()
        }
        retainUIDiagnostics("phone-control-unavailable", in: app,
                            candidates: app.descendants(matching: .any).matching(identifier: element.identifier))
        XCTFail("Control unavailable: \(element.identifier)")
    }
}
