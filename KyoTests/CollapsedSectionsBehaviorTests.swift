import XCTest

/// Which Today sections are collapsed: every section starts expanded, each toggles on its own, the
/// state lives in the injected `UserDefaults`, and starting a task draft expands Tasks.
@MainActor
final class CollapsedSectionsBehaviorTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
        suiteNames = []
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        let name = "kyo.collapsed-sections.tests.\(UUID().uuidString)"
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    func testEverySectionStartsExpandedWhenNothingIsStored() {
        let sections = CollapsedSections(defaults: makeDefaults())

        for section in TodaySectionID.allCases {
            XCTAssertFalse(sections.isCollapsed(section), "\(section)")
        }
    }

    func testTogglingCollapsesAndExpandsOneSection() {
        let sections = CollapsedSections(defaults: makeDefaults())

        sections.toggle(.habits)
        XCTAssertTrue(sections.isCollapsed(.habits))

        sections.toggle(.habits)
        XCTAssertFalse(sections.isCollapsed(.habits))
    }

    func testTogglingOneSectionLeavesTheOthersAlone() {
        let sections = CollapsedSections(defaults: makeDefaults())

        sections.toggle(.memos)

        XCTAssertTrue(sections.isCollapsed(.memos))
        XCTAssertFalse(sections.isCollapsed(.schedule))
        XCTAssertFalse(sections.isCollapsed(.tasks))
        XCTAssertFalse(sections.isCollapsed(.habits))
    }

    func testSectionsCollapseIndependently() {
        let sections = CollapsedSections(defaults: makeDefaults())

        sections.toggle(.schedule)
        sections.toggle(.tasks)
        sections.toggle(.schedule)

        XCTAssertFalse(sections.isCollapsed(.schedule))
        XCTAssertTrue(sections.isCollapsed(.tasks))
    }

    func testANewModelOnTheSameDefaultsReadsTheStateBack() {
        let defaults = makeDefaults()
        let first = CollapsedSections(defaults: defaults)
        first.toggle(.schedule)
        first.toggle(.memos)

        let second = CollapsedSections(defaults: defaults)

        XCTAssertTrue(second.isCollapsed(.schedule))
        XCTAssertFalse(second.isCollapsed(.tasks))
        XCTAssertFalse(second.isCollapsed(.habits))
        XCTAssertTrue(second.isCollapsed(.memos))
    }

    func testExpandingIsReadBackToo() {
        let defaults = makeDefaults()
        let first = CollapsedSections(defaults: defaults)
        first.toggle(.tasks)
        first.toggle(.tasks)

        XCTAssertFalse(CollapsedSections(defaults: defaults).isCollapsed(.tasks))
    }

    func testStateInOneSuiteIsNotSeenByAnother() {
        let first = CollapsedSections(defaults: makeDefaults())
        first.toggle(.tasks)

        XCTAssertFalse(CollapsedSections(defaults: makeDefaults()).isCollapsed(.tasks))
    }

    func testStartingATaskDraftExpandsACollapsedTasksSection() {
        let defaults = makeDefaults()
        let sections = CollapsedSections(defaults: defaults)
        sections.toggle(.tasks)

        sections.startTaskDraft()

        XCTAssertFalse(sections.isCollapsed(.tasks))
        XCTAssertFalse(CollapsedSections(defaults: defaults).isCollapsed(.tasks), "stays expanded after a relaunch")
    }

    func testStartingATaskDraftLeavesOtherSectionsAlone() {
        let sections = CollapsedSections(defaults: makeDefaults())
        sections.toggle(.tasks)
        sections.toggle(.habits)
        sections.toggle(.memos)

        sections.startTaskDraft()

        XCTAssertTrue(sections.isCollapsed(.habits))
        XCTAssertTrue(sections.isCollapsed(.memos))
        XCTAssertFalse(sections.isCollapsed(.schedule))
    }

    func testStartingATaskDraftWithTasksExpandedChangesNothing() {
        let sections = CollapsedSections(defaults: makeDefaults())

        sections.startTaskDraft()

        for section in TodaySectionID.allCases {
            XCTAssertFalse(sections.isCollapsed(section), "\(section)")
        }
    }
}
