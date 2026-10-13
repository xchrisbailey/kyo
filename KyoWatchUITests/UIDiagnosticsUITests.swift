import XCTest

@MainActor
final class UIDiagnosticsUITests: XCTestCase {
    func testDiagnosticsCaptureLiveCandidatesAndHierarchy() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        let candidates = app.descendants(matching: .any).matching(identifier: "plus")
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 10))
        let report = retainUIDiagnostics("diagnostic-capture", in: app, candidates: candidates)
        XCTAssertTrue(report.contains("identifier=plus"))
        XCTAssertTrue(report.contains("type="))
        XCTAssertTrue(report.contains("frame="))
        XCTAssertTrue(report.contains("hittable="))
        XCTAssertTrue(report.contains("Hierarchy:"))
        XCTAssertTrue(report.contains("Application,"))
    }
}
