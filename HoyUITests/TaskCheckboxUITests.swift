import XCTest

@MainActor
final class TaskCheckboxUITests: XCTestCase {
    func testCompletingMultipleTasksAndReopeningOne() throws {
        let app = XCUIApplication()
        app.launch()

        let runID = String(UUID().uuidString.prefix(8))
        let firstTitle = "First checkbox task \(runID)"
        let secondTitle = "Second checkbox task \(runID)"
        addTask(firstTitle, to: app)
        addTask(secondTitle, to: app)

        let firstCheckbox = app.buttons[firstTitle]
        let secondCheckbox = app.buttons[secondTitle]
        XCTAssertTrue(firstCheckbox.waitForExistence(timeout: 3))
        XCTAssertTrue(secondCheckbox.exists)

        firstCheckbox.tap()
        XCTAssertEqual(app.buttons[firstTitle].value as? String, "Completed")

        app.buttons[secondTitle].tap()
        XCTAssertEqual(app.buttons[secondTitle].value as? String, "Completed")

        app.buttons[firstTitle].tap()
        XCTAssertEqual(app.buttons[firstTitle].value as? String, "Not completed")
    }

    func testEditingTaskKeepsCheckboxSeparateAndSwipeDeletesTask() throws {
        let app = XCUIApplication()
        app.launch()

        let runID = String(UUID().uuidString.prefix(8))
        let originalTitle = "Editable task \(runID)"
        let editedTitle = "\(originalTitle) renamed"
        addTask(originalTitle, to: app)

        app.buttons["Edit task: \(originalTitle)"].tap()
        let editor = app.textFields["task-editor:\(originalTitle)"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText(" renamed\n")

        let checkbox = app.buttons[editedTitle]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 3))
        XCTAssertEqual(checkbox.value as? String, "Not completed")
        checkbox.tap()
        XCTAssertEqual(app.buttons[editedTitle].value as? String, "Completed")

        app.buttons["Edit task: \(editedTitle)"].swipeLeft()
        let deleteButton = app.buttons["Delete task: \(editedTitle)"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()
        let deletedTaskControls = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", runID))
        let deletionExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: deletedTaskControls
        )
        XCTAssertEqual(XCTWaiter.wait(for: [deletionExpectation], timeout: 3), .completed)
    }

    private func addTask(_ title: String, to app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(title + "\n")
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3))
    }
}
