import XCTest

/// Smoke test for collapsing and expanding a section on the Watch's Today view. Each launch gets its
/// own collapse state through `KYO_COLLAPSED_SECTIONS_SUITE`, so it never touches the Watch's real defaults.
/// With no paired phone the sections are empty, so the empty-state row stands in for the section's content.
@MainActor
final class WatchSectionCollapseUITests: XCTestCase {
    func testTappingTheTasksHeaderCollapsesAndExpandsTheSection() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_COLLAPSED_SECTIONS_SUITE"] = "kyo.collapsed-sections.ui-tests.\(UUID().uuidString)"
        // A throwaway theme suite takes no feed from a paired phone, so the run is always in the Kyo theme.
        app.launchEnvironment["KYO_WATCH_THEME_SUITE"] = "kyo.watch-theme.ui-tests.\(UUID().uuidString)"
        app.launch()

        let header = app.buttons["section-header-tasks"]
        let content = app.staticTexts["No tasks yet"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.value as? String, "expanded")
        // The list is lazy and the Watch screen is small, so the row sits below what's drawn until the list scrolls.
        scrollUntilVisible(content, in: app)
        XCTAssertTrue(content.exists)

        header.tap()

        XCTAssertTrue(waitForValue("collapsed", of: header))
        XCTAssertFalse(content.waitForExistence(timeout: 1))

        header.tap()

        XCTAssertTrue(waitForValue("expanded", of: header))
        scrollUntilVisible(content, in: app)
        XCTAssertTrue(content.exists)
    }

    /// Drags the list up a little at a time, keeping the section header on screen, until `element` is drawn.
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 3) {
        for _ in 0..<attempts where !element.exists {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        }
    }

    private func waitForValue(_ value: String, of element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
