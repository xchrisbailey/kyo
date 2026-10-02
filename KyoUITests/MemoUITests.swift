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

    func testDiscardingARecordingSavesNothing() throws {
        let app = launchIsolatedApp()
        openRecorder(in: app)

        app.buttons["Discard"].tap()

        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 3))
    }

    func testRecordingAVoiceMemoThenOpeningAndDeletingItWithConfirmation() throws {
        let app = launchIsolatedApp()
        openRecorder(in: app)
        Thread.sleep(forTimeInterval: 1.5)

        app.buttons["Stop"].tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Voice memo. '")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 memo"].exists)

        // Opening the card shows the pinned player and No transcript with Try again.
        row.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 3))
        app.buttons["Delete memo"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 3))
    }

    func testDeletingAVoiceMemoFromItsRowConfirmsFirst() throws {
        let app = launchIsolatedApp()
        openRecorder(in: app)
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Stop"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Voice memo. '")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        XCTAssertTrue(row.exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        row.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 3))
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

    /// Opens the recorder from the + menu and allows the microphone if the system asks.
    private func openRecorder(in app: XCUIApplication) {
        app.buttons["Add an item"].tap()
        app.buttons["Voice memo"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
