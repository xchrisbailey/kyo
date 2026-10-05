import XCTest

@MainActor
final class MemoUITests: XCTestCase {
    func testEmptyMemosSectionAndTheVoiceMemoEntry() throws {
        let app = launchIsolatedApp()

        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Memos, Notes & voice"].exists)

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
        XCTAssertTrue(app.buttons["Memos, 1 memo"].exists)
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
        XCTAssertTrue(app.buttons["Memos, Notes & voice"].exists)
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

    func testMemoToTaskOpensTheManualSheetAndAddsATypedTaskToToday() throws {
        let app = launchIsolatedApp()

        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 3))
        compose.typeText("Plan the weekend")
        app.buttons["Save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Plan the weekend.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()

        // UI test launches have no Apple Intelligence, so the manual sheet opens.
        let memoToTask = app.buttons["Memo → Task"]
        XCTAssertTrue(memoToTask.waitForExistence(timeout: 3))
        memoToTask.tap()
        XCTAssertTrue(app.staticTexts["No suggestions"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add another"].exists)
        XCTAssertTrue(app.buttons["Add to Today (0)"].exists)

        let task = app.textFields["Task"].firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        task.tap()
        task.typeText("Book the trail")
        let add = app.buttons["Add to Today (1)"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(app.staticTexts["Added"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add to Today (0)"].exists)
    }

    func testLongPressingAMemoRowOffersShareAboveDeleteOnTodayAndInMemoHistory() throws {
        let app = launchIsolatedApp()

        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 3))
        compose.typeText("Weekend idea\nTry the trail")
        app.buttons["Save"].tap()

        let rowPredicate = NSPredicate(format: "label BEGINSWITH 'Written memo. Weekend idea.'")
        let todayRow = app.buttons.matching(rowPredicate).firstMatch
        XCTAssertTrue(todayRow.waitForExistence(timeout: 3))
        assertMenuOffersShareAboveDelete(from: todayRow, in: app)

        app.buttons["See all"].tap()
        XCTAssertTrue(app.navigationBars["Memos"].waitForExistence(timeout: 3))
        let historyRow = app.buttons.matching(rowPredicate).firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 3))
        assertMenuOffersShareAboveDelete(from: historyRow, in: app)

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("trail")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Weekend idea.'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        assertMenuOffersShareAboveDelete(from: result, in: app)
    }

    /// Long-presses `row`, checks the menu has Share above Delete, then closes the menu.
    private func assertMenuOffersShareAboveDelete(from row: XCUIElement, in app: XCUIApplication) {
        row.press(forDuration: 1)
        let share = app.buttons["Share"]
        let delete = app.buttons["Delete"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        XCTAssertTrue(delete.exists)
        XCTAssertLessThan(share.frame.minY, delete.frame.minY)
        // Tapping outside the menu closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        XCTAssertTrue(share.waitForNonExistence(timeout: 3))
    }

    func testSeeAllOpensTheMemosSheetWithTodayAndSearch() throws {
        let app = launchIsolatedApp()
        XCTAssertFalse(app.buttons["See all"].exists)

        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 3))
        compose.typeText("Weekend idea\nTry the trail")
        app.buttons["Save"].tap()

        let seeAll = app.buttons["See all"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 3))
        seeAll.tap()

        XCTAssertTrue(app.navigationBars["Memos"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Today"].exists)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Weekend idea.'")).firstMatch
        XCTAssertTrue(row.exists)

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("zebra")
        XCTAssertTrue(app.staticTexts["No memos match \u{201C}zebra\u{201D}"].waitForExistence(timeout: 3))
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
