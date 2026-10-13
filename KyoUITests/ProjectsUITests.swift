import XCTest

@MainActor
final class ProjectsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testChoosingProjectWorkShowsGroupNavigationCaptureCompletionAndCollapse() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        tapRevealed(app.buttons["section-link-projects"], in: app)
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Build Kyo and a daily planner for every device")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        let projectID = String(project.identifier.dropFirst("project-open-".count))
        project.tap()
        app.buttons["project-add-task"].tap()
        let task = app.textFields["project-task-editor"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        task.typeText("Widgets")
        app.buttons["project-task-save"].tap()
        let choose = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-do-today-")).firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        app.buttons["projects-done"].tap()
        let group = app.buttons["project-group-collapse-\(projectID)"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertEqual(group.value as? String, "expanded")
        XCTAssertEqual(app.staticTexts["project-group-summary-\(projectID)"].label, "0 of 1 done")
        tapRevealed(group, in: app)
        XCTAssertEqual(group.value as? String, "collapsed")
        tapRevealed(app.buttons["project-group-open-\(projectID)"], in: app)
        let completed = app.buttons["project-completed-collapse-\(projectID)"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertEqual(completed.value as? String, "expanded")
        completed.tap()
        app.buttons["projects-done"].tap()
        XCTAssertEqual(group.value as? String, "collapsed")
        tapRevealed(group, in: app)
        tapRevealed(app.buttons["project-group-add-\(projectID)"], in: app)
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        task.typeText("Sync")
        app.buttons["project-task-save"].tap()
        XCTAssertEqual(app.staticTexts["project-group-summary-\(projectID)"].label, "0 of 2 done")
        let checkbox = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-")).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        tapRevealed(checkbox, in: app)
        XCTAssertEqual(app.staticTexts["project-group-summary-\(projectID)"].label, "1 of 2 done")
        XCTAssertEqual(app.descendants(matching: .any)["task-count-summary"].value as? String, "1 / 2 tasks done")
        capture("project-today-group-long-name", in: app)
    }

    func testProjectNavigationCaptureRenameAndIndependentCollapsedHeaderLink() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        selectTheme("neko", palette: "Light", in: app)
        let header = app.buttons["section-header-projects"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.value as? String, "expanded")
        XCTAssertEqual(app.staticTexts["projects-empty"].label, "No project tasks for today")
        header.tap()
        XCTAssertEqual(header.value as? String, "collapsed")
        app.buttons["section-link-projects"].tap()
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture("projects-neko-light-new-project", in: app)
        name.tap()
        name.typeText("Kyo")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertEqual(project.label, "Kyo")
        capture("all-projects-neko-light", in: app)
        project.tap()
        app.buttons["project-add-task"].tap()
        let task = app.textFields["project-task-editor"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        capture("project-task-form-neko-light", in: app)
        task.tap()
        task.typeText("Explore widgets")
        app.buttons["project-task-save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-edit-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Edit task: Explore widgets")
        capture("project-detail-neko-light", in: app)
        let id = String(row.identifier.dropFirst("task-edit-".count))
        row.tap()
        let editor = app.textFields["task-editor-\(id)"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 15) + "Build widgets\n")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Edit task: Build widgets")
        row.swipeLeft()
        app.buttons["task-delete-\(id)"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        app.buttons["project-rename"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "Build Kyo")
        app.buttons["project-name-save"].tap()
        app.buttons["projects-done"].tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.value as? String, "collapsed")
        XCTAssertEqual(app.buttons["section-header-tasks"].label, "Tasks, For today")
    }

    func testEmptyTodayNewProjectOpensCaptureDirectly() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        selectTheme("techo", palette: "Dark", in: app)
        let create = app.buttons["projects-new"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture("projects-techo-dark-new-project", in: app)
        name.tap()
        name.typeText("House")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertEqual(project.label, "House")
        capture("all-projects-techo-dark", in: app)
        project.tap()
        XCTAssertTrue(app.buttons["project-add-task"].waitForExistence(timeout: 5))
        capture("project-detail-techo-dark", in: app)
    }
    private func tapRevealed(_ control: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let bottom = app.buttons["add-item"].frame.minY - 12
            if control.isHittable && control.frame.maxY < bottom && control.frame.minY >= scroll.frame.minY {
                control.tap()
                return
            }
            if control.frame.maxY >= bottom { scroll.swipeUp() }
            else { scroll.swipeDown() }
        }
        XCTFail("Control remained outside the visible Today scroll area: \(control.identifier)")
    }

    private func selectTheme(_ id: String, palette: String, in app: XCUIApplication) {
        app.buttons["settings-button"].tap()
        let theme = app.buttons["theme-card-\(id)"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        theme.tap()
        let picker = app.segmentedControls["palette-picker"]
        picker.buttons[palette].tap() // label-query: native palette segments have no identifiers
        app.buttons["settings-done"].tap()
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
