import XCTest

@MainActor
final class ProjectMemoUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testProjectCaptureAssignmentRemovalAndEverydayCapturePicker() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
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
        let projectID = String(project.identifier.dropFirst("project-open-".count))
        project.tap()
        app.buttons["project-add-memo"].tap()
        let write = app.buttons["project-add-written-memo"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        let compose = app.textFields["memo-compose-text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["memo-project-picker"].value as? String, "Kyo")
        compose.typeText("Project thought")
        app.buttons["memo-compose-save"].tap()
        let memo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-memo-open-")).firstMatch
        XCTAssertTrue(memo.waitForExistence(timeout: 5))
        XCTAssertEqual(memo.label, "Project thought")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "project-memo-list"
        capture.lifetime = .keepAlways
        add(capture)
        memo.tap()
        let move = app.buttons["memo-project-move"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertEqual(move.value as? String, "Kyo")
        move.tap()
        app.buttons["memo-project-remove"].tap()
        XCTAssertEqual(move.value as? String, "No project")
        app.buttons["memo-close"].tap()
        XCTAssertTrue(memo.waitForNonExistence(timeout: 5))
        app.buttons["projects-done"].tap()
        app.buttons["add-item"].tap()
        app.buttons["Written memo"].tap() // label-query: existing memo capture route
        XCTAssertTrue(compose.waitForExistence(timeout: 5))
        let picker = app.buttons["memo-project-picker"]
        XCTAssertEqual(picker.value as? String, "No project")
        picker.tap()
        app.buttons["memo-project-option-\(projectID)"].tap()
        XCTAssertEqual(picker.value as? String, "Kyo")
        compose.tap()
        compose.typeText("Everyday capture in project")
        app.buttons["memo-compose-save"].tap()
        openProjects(in: app)
        project.tap()
        XCTAssertTrue(memo.waitForExistence(timeout: 5))
        XCTAssertEqual(memo.label, "Everyday capture in project")
    }
}
