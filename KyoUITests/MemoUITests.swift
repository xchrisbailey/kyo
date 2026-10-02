import XCTest

@MainActor
final class MemoUITests: XCTestCase {
    func testEmptyMemosSectionAndTheVoiceMemoEntry() throws {
        let app = launchIsolatedApp()

        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Notes & voice"].exists)

        app.buttons["Add an item"].tap()
        XCTAssertTrue(app.buttons["Written memo"].waitForExistence(timeout: 3))
        let voice = app.buttons["Voice memo"]
        XCTAssertTrue(voice.exists)
        XCTAssertTrue(voice.isEnabled)
    }

    func testWritingOpeningEditingAndDeletingAMemo() throws {
        let app = launchIsolatedApp()

        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 3))
        compose.typeText("Weekend idea\nTry the trail")
        app.buttons["Save"].tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Weekend idea.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1 memo"].exists)
        XCTAssertFalse(app.staticTexts["Tap + to add a memo"].exists)

        row.tap()
        let editor = app.textFields["Memo text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete memo"].exists)
        editor.tap()
        editor.typeText("Edited: ")
        app.buttons["Close memo"].tap()

        let edited = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Edited: Weekend idea.'")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 3))

        edited.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Notes & voice"].exists)
    }

    func testSavingAnEmptyMemoDiscardsItAndEmptyingAnOpenMemoDiscardsItOnClose() throws {
        let app = launchIsolatedApp()

        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        XCTAssertTrue(app.textFields["Memo text"].waitForExistence(timeout: 3))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 3))

        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 3))
        compose.typeText("Short-lived")
        app.buttons["Save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Short-lived.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        row.tap()
        let editor = app.textFields["Memo text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.press(forDuration: 1.2)
        app.menuItems["Select All"].tap()
        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        app.buttons["Close memo"].tap()

        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 3))
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
