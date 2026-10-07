import XCTest

@MainActor
final class MemoUITests: XCTestCase {
    /// M10. The memo lifecycle on Today: the empty state and Add menu entries, writing a memo, opening and editing it,
    /// turning it into a task through the manual sheet, and deleting it from its context menu.
    func testMemoLifecycleFromEmptyThroughWritingEditingMemoToTaskAndDeleting() throws {
        let app = launchIsolatedApp()

        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Memos, Notes & voice"].exists)
        XCTAssertFalse(app.buttons["See all"].exists)

        app.buttons["Add an item"].tap()
        XCTAssertTrue(app.buttons["Written memo"].waitForExistence(timeout: 10))
        let voice = app.buttons["Voice memo"]
        XCTAssertTrue(voice.exists)
        XCTAssertTrue(voice.isEnabled)

        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        compose.typeText("Weekend idea\nTry the trail")
        app.buttons["Save"].tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Weekend idea.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Memos, 1 memo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Tap + to add a memo"].exists)

        row.tap()
        let editor = app.textFields["Memo text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Delete memo"].exists)
        editor.tap()
        editor.typeText("Edited: ")

        // UI test launches have no Apple Intelligence, so Memo → Task opens the manual sheet.
        let memoToTask = app.buttons["Memo → Task"]
        XCTAssertTrue(memoToTask.waitForExistence(timeout: 10))
        memoToTask.tap()
        XCTAssertTrue(app.staticTexts["No suggestions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add another"].exists)
        XCTAssertTrue(app.buttons["Add to Today (0)"].exists)

        let task = app.textFields["Task"].firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.tap()
        task.typeText("Book the trail")
        let add = app.buttons["Add to Today (1)"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.staticTexts["Added"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add to Today (0)"].exists)

        app.navigationBars["Memo → Task"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Memo → Task"].waitForNonExistence(timeout: 10))
        app.buttons["Close memo"].tap()

        let edited = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Written memo. Edited: Weekend idea.'")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Book the trail"].waitForExistence(timeout: 10), "the added task is on Today")

        edited.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Tap + to add a memo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Memos, Notes & voice"].exists)
    }

    /// M11. A memo's context menu on Today and in the Memos sheet, the sheet's Today group, and its search.
    func testMemoHistorySheetMenusAndSearch() throws {
        let app = launchIsolatedApp()
        XCTAssertFalse(app.buttons["See all"].exists)

        app.buttons["Add an item"].tap()
        app.buttons["Written memo"].tap()
        let compose = app.textFields["Memo text"]
        XCTAssertTrue(compose.waitForExistence(timeout: 10))
        compose.typeText("Weekend idea\nTry the trail")
        app.buttons["Save"].tap()

        let rowPredicate = NSPredicate(format: "label BEGINSWITH 'Written memo. Weekend idea.'")
        let todayRow = app.buttons.matching(rowPredicate).firstMatch
        XCTAssertTrue(todayRow.waitForExistence(timeout: 10))
        assertMenuOffersShareAboveDelete(from: todayRow, in: app)

        let seeAll = app.buttons["See all"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 10))
        seeAll.tap()
        XCTAssertTrue(app.navigationBars["Memos"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Today"].exists)
        let historyRow = sheetRow(matching: rowPredicate, behind: todayRow, in: app)
        assertMenuOffersShareAboveDelete(from: historyRow, in: app)

        // A search that hits keeps the row; extending it to something no memo contains says so.
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("trail")
        _ = sheetRow(matching: rowPredicate, behind: todayRow, in: app)
        search.typeText("x")
        XCTAssertTrue(app.staticTexts["No memos match \u{201C}trailx\u{201D}"].waitForExistence(timeout: 10))
    }

    /// The row in the Memos sheet. Today's row is still in the hierarchy behind the sheet, so
    /// there must be two matches: Today's, which the sheet covers, and the sheet's own, which is
    /// the one on top. Fails if the sheet shows no such row.
    private func sheetRow(
        matching predicate: NSPredicate, behind todayRow: XCUIElement, in app: XCUIApplication
    ) -> XCUIElement {
        let rows = app.buttons.matching(predicate)
        let row = rows.element(boundBy: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(row.isHittable)
        XCTAssertFalse(todayRow.isHittable)
        return row
    }

    /// Long-presses `row`, checks the menu has Share above Delete, then closes the menu.
    private func assertMenuOffersShareAboveDelete(from row: XCUIElement, in app: XCUIApplication) {
        row.press(forDuration: 1)
        let share = app.buttons["Share"]
        let delete = app.buttons["Delete"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(delete.exists)
        XCTAssertLessThan(share.frame.minY, delete.frame.minY)
        // Tapping outside the menu closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()
        XCTAssertTrue(share.waitForNonExistence(timeout: 10))
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        return app
    }
}
