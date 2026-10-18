import XCTest

@MainActor
final class ProjectTaskDraftPreferenceUITests: XCTestCase {
    func testTodayProjectTaskDraftSurvivesRemoteOptOutDuringBackground() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launchEnvironment["KYO_PROJECTS_ENABLED"] = "1"
        app.launchEnvironment["KYO_PROJECTS_DISABLE_AFTER_BACKGROUND"] = "1"
        app.launchEnvironment["KYO_PROJECTS_PREFERENCE_SUITE"] = "kyo.projectTaskDraft.ui-tests.\(UUID().uuidString)"
        app.launch()
        openProjects(in: app)
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Kyo")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        let id = String(project.identifier.dropFirst("project-open-".count))
        project.tap()
        app.buttons["project-add-task"].tap()
        let task = app.textFields["project-task-editor"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        task.typeText("Existing")
        app.buttons["project-task-today"].tap()
        app.buttons["project-task-save"].tap()
        app.buttons["projects-done"].tap()
        let add = app.buttons["project-group-add-\(id)"]
        for _ in 0..<5 where !add.isHittable { app.scrollViews.firstMatch.swipeUp() }
        add.tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        task.typeText("Keep this draft")
        XCTAssertEqual(task.value as? String, "Keep this draft")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(task.value as? String, "Keep this draft")
        app.buttons["project-task-save"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "task-checkbox-", "Keep this draft")).firstMatch // label-query: identifies the captured task whose text must survive the opt-out
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["section-header-projects"].exists)
        let settings = app.buttons["settings-button"]
        for _ in 0..<8 where !settings.isHittable { app.scrollViews.firstMatch.swipeDown() }
        settings.tap()
        let toggle = app.switches["settings-projects-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "the real preference store received the remote off record")
        toggle.switches.firstMatch.tap()
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.buttons["project-group-open-\(id)"].waitForExistence(timeout: 5))
        XCTAssertTrue(saved.exists, "the new task retained its project membership")
    }
}
