import Combine
import XCTest

/// What Month shows for each day once the four kinds have content, driven by stand-in sources.
/// Today is Tuesday 6 October 2026. The orders asserted here (marks, spoken phrases, Day summary
/// sections) are fixed whatever order the sources arrive in.
@MainActor
final class MonthContentBehaviorTests: XCTestCase {
    private let harness = MonthHarness(2026, 10, 6)

    private func row(_ text: String) -> MonthSummaryRow { MonthSummaryRow(id: text, text: text) }

    private func day(_ number: Int, in model: MonthModel) throws -> MonthDay {
        try XCTUnwrap(model.weeks.flatMap(\.cells).compactMap(\.day).first { $0.number == number })
    }

    private func standIn(_ kind: MonthKind, _ days: [Int: MonthKindDay]) -> StandInMonthContent {
        let source = StandInMonthContent(kind)
        source.content = Dictionary(uniqueKeysWithValues: days.map { (harness.date(2026, 10, $0.key, hour: 0), $0.value) })
        return source
    }

    /// Every kind has content on the 5th, given to the model in reverse order.
    private func fullDay() -> [StandInMonthContent] {
        [
            standIn(.memos, [5: MonthKindDay(mark: .filled, phrase: "1 memo", rows: [row("Call Sam")])]),
            standIn(.habits, [5: MonthKindDay(mark: .hollow, phrase: "some habits done", rows: [row("Stretch")])]),
            standIn(.tasks, [5: MonthKindDay(mark: .filled, phrase: "3 tasks completed", rows: [row("Pay rent")])]),
            standIn(.events, [5: MonthKindDay(mark: .filled, phrase: "2 events", rows: [row("Standup")])]),
        ]
    }

    // MARK: Marks

    func testEveryDayHasFourMarkSlotsAndAllAreEmptyWithoutContent() throws {
        let model = harness.makeModel()

        for week in model.weeks {
            for cell in week.cells {
                if let day = cell.day { XCTAssertEqual(day.marks, [.empty, .empty, .empty, .empty], "day \(day.number)") }
            }
        }
    }

    func testMarksSitInTheSlotsForEventsTasksHabitsAndMemosWhateverTheSourceOrder() throws {
        let model = harness.makeModel(sources: [
            standIn(.memos, [3: MonthKindDay(mark: .filled)]),
            standIn(.events, [3: MonthKindDay(mark: .filled)]),
            standIn(.habits, [3: MonthKindDay(mark: .hollow), 4: MonthKindDay(mark: .filled)]),
        ])

        XCTAssertEqual(try day(3, in: model).marks, [.filled, .empty, .hollow, .filled])
        XCTAssertEqual(try day(4, in: model).marks, [.empty, .empty, .filled, .empty])
        XCTAssertEqual(try day(5, in: model).marks, [.empty, .empty, .empty, .empty])
    }

    // MARK: VoiceOver

    func testADayReadsItsDateThenEventsTasksHabitsAndMemosInThatOrder() throws {
        let model = harness.makeModel(sources: fullDay())

        XCTAssertEqual(
            try day(5, in: model).accessibilityLabel,
            "Monday, October 5, 2 events, 3 tasks completed, some habits done, 1 memo"
        )
    }

    func testAKindWithNothingLeavesNoPhraseInTheLabel() throws {
        let model = harness.makeModel(sources: [
            standIn(.memos, [5: MonthKindDay(mark: .filled, phrase: "1 memo")]),
            standIn(.events, [5: MonthKindDay(mark: .filled, phrase: "2 events")]),
        ])

        XCTAssertEqual(try day(5, in: model).accessibilityLabel, "Monday, October 5, 2 events, 1 memo")
        XCTAssertEqual(try day(4, in: model).accessibilityLabel, "Sunday, October 4")
    }

    func testTodaysLabelSaysSoAfterItsDate() throws {
        let model = harness.makeModel(sources: [standIn(.tasks, [6: MonthKindDay(mark: .filled, phrase: "1 task completed")])])

        XCTAssertEqual(try day(6, in: model).accessibilityLabel, "Tuesday, October 6, Today, 1 task completed")
    }

    // MARK: Day summary

    func testAnEmptyDayHasAnEmptyDaySummary() {
        let model = harness.makeModel(sources: fullDay())

        XCTAssertTrue(model.selectedSummary.isEmpty)
        XCTAssertTrue(model.selectedSummary.sections.isEmpty)
    }

    func testTheDaySummaryListsEventsTasksHabitsAndMemosInThatOrderWhateverTheSourceOrder() {
        let model = harness.makeModel(sources: fullDay())

        model.select(harness.date(2026, 10, 5))

        XCTAssertFalse(model.selectedSummary.isEmpty)
        XCTAssertEqual(model.selectedSummary.sections.map(\.kind), [.events, .tasks, .habits, .memos])
        XCTAssertEqual(model.selectedSummary.sections.map { $0.rows.map(\.text) }, [["Standup"], ["Pay rent"], ["Stretch"], ["Call Sam"]])
    }

    func testTheDaySummaryOmitsAKindWithNoRows() {
        let model = harness.makeModel(sources: [
            standIn(.memos, [5: MonthKindDay(mark: .filled, rows: [row("Call Sam")])]),
            standIn(.tasks, [5: MonthKindDay(mark: .empty, rows: [])]),
            standIn(.events, [5: MonthKindDay(mark: .filled, rows: [row("Standup")])]),
        ])

        model.select(harness.date(2026, 10, 5))

        XCTAssertEqual(model.selectedSummary.sections.map(\.kind), [.events, .memos])
    }

    func testTheDaySummaryKeepsEachKindsRowsInTheOrderTheSourceGaveThem() {
        let model = harness.makeModel(sources: [
            standIn(.events, [5: MonthKindDay(mark: .filled, rows: [row("All day"), row("Standup"), row("Lunch")])]),
        ])

        model.select(harness.date(2026, 10, 5))

        XCTAssertEqual(model.selectedSummary.sections.first?.rows.map(\.text), ["All day", "Standup", "Lunch"])
    }

    // MARK: The days content is computed for

    func testSourcesAreAskedAboutEveryDayOfTheShownMonthAndNoOthers() throws {
        let source = standIn(.events, [:])
        _ = harness.makeModel(sources: [source])

        let asked = try XCTUnwrap(source.requests.last)
        XCTAssertEqual(asked, (1...31).map { harness.date(2026, 10, $0, hour: 0) })
    }

    func testContentForADayOutsideTheShownMonthIsIgnored() throws {
        let model = harness.makeModel(sources: [
            ForcedContent(kind: .events, content: [harness.date(2026, 9, 30, hour: 0): MonthKindDay(mark: .filled, phrase: "1 event")]),
        ])

        let days = model.weeks.flatMap(\.cells).compactMap(\.day)
        XCTAssertTrue(days.allSatisfy { $0.marks == [.empty, .empty, .empty, .empty] })
    }

    // MARK: Days after Today

    func testADayAfterTodayCarriesOnlyTheEventKind() throws {
        let everything = MonthKindDay(mark: .filled, phrase: "1 thing", rows: [row("A thing")])
        let model = harness.makeModel(sources: MonthKind.allCases.map { standIn($0, [7: everything]) })

        let tomorrow = try day(7, in: model)
        XCTAssertEqual(tomorrow.marks, [.filled, .empty, .empty, .empty])
        XCTAssertEqual(tomorrow.accessibilityLabel, "Wednesday, October 7, 1 thing")
        model.select(harness.date(2026, 10, 7))
        XCTAssertEqual(model.selectedSummary.sections.map(\.kind), [.events])
    }

    func testTodayAndEarlierDaysCarryEveryKind() throws {
        let everything = MonthKindDay(mark: .filled, phrase: "1 thing", rows: [row("A thing")])
        let model = harness.makeModel(sources: MonthKind.allCases.map { standIn($0, [6: everything]) })

        XCTAssertEqual(try day(6, in: model).marks, [.filled, .filled, .filled, .filled])
        XCTAssertEqual(model.selectedSummary.sections.map(\.kind), MonthKind.allCases)
    }

    // MARK: Changes

    func testMarksAndTheDaySummaryFollowASourceWhenItsContentChanges() throws {
        let tasks = standIn(.tasks, [:])
        let model = harness.makeModel(sources: [tasks])
        XCTAssertEqual(try day(6, in: model).marks, [.empty, .empty, .empty, .empty])
        XCTAssertTrue(model.selectedSummary.isEmpty)

        tasks.content = [harness.date(2026, 10, 6, hour: 0): MonthKindDay(mark: .filled, rows: [row("Pay rent")])]

        XCTAssertEqual(try day(6, in: model).marks, [.empty, .filled, .empty, .empty])
        XCTAssertEqual(model.selectedSummary.sections.map(\.kind), [.tasks])
    }
}

/// A source that answers with fixed content whatever it is asked, even for days nobody asked about.
@MainActor
private final class ForcedContent: MonthContentSource {
    let kind: MonthKind
    let content: [Date: MonthKindDay]

    init(kind: MonthKind, content: [Date: MonthKindDay]) {
        self.kind = kind
        self.content = content
    }

    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func content(on days: [Date]) -> [Date: MonthKindDay] { content }
}
