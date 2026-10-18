import XCTest

@MainActor
final class ProjectsOptInUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDefaultOffAndDisablingPreservesDailyTaskAndMemoAccessWithoutProjectControls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["section-header-tasks"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["section-header-projects"].exists)
        app.buttons["settings-button"].tap()
        let toggle = app.switches["settings-projects-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.buttons["settings-all-projects"].exists)
        toggle.switches.firstMatch.tap()
        app.buttons["settings-all-projects"].tap()
        XCTAssertTrue(app.buttons["project-new"].waitForExistence(timeout: 5))
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Kyo")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        let projectID = String(project.identifier.dropFirst("project-open-".count))
        project.tap()
        app.buttons["project-add-task"].tap()
        let taskEditor = app.textFields["project-task-editor"]
        XCTAssertTrue(taskEditor.waitForExistence(timeout: 5))
        taskEditor.tap()
        taskEditor.typeText("Keep daily access")
        app.buttons["project-task-today"].tap()
        app.buttons["project-task-save"].tap()
        let checkbox = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-")).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        let taskID = String(checkbox.identifier.dropFirst("task-checkbox-".count))
        app.buttons["project-add-memo"].tap()
        app.buttons["project-add-written-memo"].tap()
        let compose = app.textFields["memo-compose-text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 5))
        compose.typeText("Keep memo access")
        app.buttons["memo-compose-save"].tap()
        app.buttons["projects-done"].tap()
        revealAndTap(app.buttons["settings-button"], in: app)
        toggle.switches.firstMatch.tap()
        XCTAssertFalse(app.buttons["settings-all-projects"].exists)
        app.buttons["settings-done"].tap()
        XCTAssertFalse(app.buttons["section-header-projects"].exists)
        XCTAssertTrue(app.buttons["task-checkbox-\(taskID)"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-")).count, 1)
        app.buttons["task-edit-\(taskID)"].tap()
        XCTAssertFalse(app.buttons["task-move-project-\(taskID)"].exists)
        XCTAssertFalse(app.buttons["task-remove-project-\(taskID)"].exists)
        let editor = app.textFields["task-editor-\(taskID)"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("\n")
        app.buttons["add-item"].tap()
        app.buttons["add-item-written-memo"].tap()
        XCTAssertTrue(compose.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["memo-project-picker"].exists)
        app.buttons["memo-compose-cancel"].tap()
        let memo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "memo-open-")).firstMatch
        revealAndTap(memo, in: app)
        XCTAssertTrue(app.textFields["memo-text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["memo-project-move"].exists)
        app.buttons["memo-close"].tap()
        openProjects(in: app)
        app.buttons["project-open-\(projectID)"].tap()
        XCTAssertTrue(app.buttons["task-checkbox-\(taskID)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-memo-open-")).firstMatch.exists)
    }

    private func revealAndTap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
        if !element.isHittable {
            for _ in 0..<12 where !element.isHittable { app.scrollViews.firstMatch.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
}
