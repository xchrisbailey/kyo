import XCTest

@MainActor
final class ProjectsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
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
        let row = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-task-text-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Explore widgets")
        capture("project-detail-neko-light", in: app)
        let id = String(row.identifier.dropFirst("project-task-text-".count))
        app.buttons["project-task-edit-\(id)"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        task.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 15) + "Build widgets")
        app.buttons["project-task-save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Build widgets")
        app.buttons["project-task-delete-\(id)"].tap()
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
