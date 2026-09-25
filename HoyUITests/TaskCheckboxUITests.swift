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

    private func addTask(_ title: String, to app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        let field = app.textFields["New task"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(title + "\n")
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3))
    }
}
