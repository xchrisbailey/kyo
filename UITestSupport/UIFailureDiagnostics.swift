import XCTest

@MainActor
extension XCTestCase {
    /// Retain diagnostics before an assertion aborts the test or the runner removes its simulator.
    @discardableResult
    func retainUIDiagnostics(_ name: String, in app: XCUIApplication, candidates: XCUIElementQuery) -> String {
        let inventory = candidates.allElementsBoundByIndex.map { element in
            "identifier=\(element.identifier), type=\(element.elementType.rawValue), label=\(element.label), value=\(String(describing: element.value)), frame=\(element.frame), hittable=\(element.isHittable)"
        }.joined(separator: "\n")
        let text = "Candidates:\n\(inventory)\n\nHierarchy:\n\(app.debugDescription)"
        let hierarchy = XCTAttachment(string: text)
        hierarchy.name = "\(name)-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name)-screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print(text)
        return text
    }
}
