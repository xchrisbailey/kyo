import XCTest

/// Moving between months, jumping back to the current one, and the day rolling over while Month is showing.
/// Today is Tuesday 6 October 2026 unless a test moves the clock.
@MainActor
final class MonthNavigationBehaviorTests: MonthTestCase {
    private let harness = MonthHarness(2026, 10, 6)

    private func selectedNumbers(in model: MonthModel) -> [Int] {
        model.weeks.flatMap(\.cells).compactMap(\.day).filter(\.isSelected).map(\.number)
    }

    private func todayNumbers(in model: MonthModel) -> [Int] {
        model.weeks.flatMap(\.cells).compactMap(\.day).filter(\.isToday).map(\.number)
    }

    // MARK: Previous and next

    func testNextAndPreviousShowTheNeighbouringMonthsWithTheirHeaders() {
        let model = harness.makeModel()

        model.showNextMonth()
        XCTAssertEqual(model.headerText, "November 2026")
        XCTAssertEqual(model.weeks.flatMap(\.cells).compactMap(\.day).count, 30)

        model.showPreviousMonth()
        model.showPreviousMonth()
        XCTAssertEqual(model.headerText, "September 2026")
        XCTAssertEqual(model.weeks.flatMap(\.cells).compactMap(\.day).count, 30)
    }

    func testMovingForwardAcrossAYearBoundary() {
        let model = harness.makeModel()

        for _ in 0..<3 { model.showNextMonth() }
        XCTAssertEqual(model.headerText, "January 2027")

        model.showPreviousMonth()
        XCTAssertEqual(model.headerText, "December 2026")
    }

    func testMovingBackAcrossAYearBoundary() {
        let model = MonthHarness(2026, 1, 15).makeModel()

        model.showPreviousMonth()
        XCTAssertEqual(model.headerText, "December 2025")
    }

    func testThereIsNoLimitInEitherDirection() {
        let model = harness.makeModel()

        for _ in 0..<(12 * 50) { model.showNextMonth() }
        XCTAssertEqual(model.headerText, "October 2076")

        for _ in 0..<(12 * 100) { model.showPreviousMonth() }
        XCTAssertEqual(model.headerText, "October 1976")
    }

    func testTheGridFollowsTheShownMonthsLayout() {
        let model = harness.makeModel()

        model.showNextMonth()

        // November 2026 starts on a Sunday and has 30 days.
        XCTAssertEqual(model.weeks.first?.cells.map { $0.day?.number }, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(model.weeks.count, 5)
        XCTAssertEqual(model.weeks.last?.cells.map { $0.day?.number }, [29, 30, nil, nil, nil, nil, nil])
    }

    // MARK: The current month

    func testTheJumpBackControlIsNeededOnlyOutsideTheCurrentMonth() {
        let model = harness.makeModel()
        XCTAssertTrue(model.isShowingCurrentMonth)

        model.showNextMonth()
        XCTAssertFalse(model.isShowingCurrentMonth)

        model.showPreviousMonth()
        XCTAssertTrue(model.isShowingCurrentMonth)

        model.showPreviousMonth()
        XCTAssertFalse(model.isShowingCurrentMonth)
    }

    func testJumpingBackReturnsToTheCurrentMonthAndSelectsToday() throws {
        let model = harness.makeModel()
        model.select(harness.date(2026, 10, 20))
        model.showNextMonth()
        model.showNextMonth()
        model.select(harness.date(2026, 12, 25))

        model.showCurrentMonth()

        XCTAssertEqual(model.headerText, "October 2026")
        XCTAssertTrue(model.isShowingCurrentMonth)
        XCTAssertEqual(selectedNumbers(in: model), [6])
        XCTAssertTrue(try day(6, in: model).isToday)
    }

    // MARK: What is selected after moving

    func testMovingToAMonthWithoutTheSelectedDayShowsItsFirstDayAsSelected() throws {
        let events = StandInMonthContent(.events)
        events.content = [harness.date(2026, 11, 1, hour: 0): MonthKindDay(mark: .filled, phrase: "1 event", rows: [row("Parade")])]
        let model = harness.makeModel(sources: [events])
        model.select(harness.date(2026, 10, 15))

        model.showNextMonth()

        XCTAssertEqual(selectedNumbers(in: model), [1])
        XCTAssertEqual(model.selectedSummary.title, "Sunday, November 1")
        XCTAssertEqual(model.selectedSummary.sections.first?.rows.map(\.text), ["Parade"])
    }

    func testTheUsersSelectionComesBackWhenTheirMonthIsShownAgain() {
        let model = harness.makeModel()
        model.select(harness.date(2026, 10, 15))

        model.showNextMonth()
        model.showPreviousMonth()

        XCTAssertEqual(selectedNumbers(in: model), [15])
    }

    func testSelectingADayInAnotherMonthSticksThere() {
        let model = harness.makeModel()
        model.showNextMonth()

        model.select(harness.date(2026, 11, 12))

        XCTAssertEqual(selectedNumbers(in: model), [12])
        XCTAssertEqual(model.selectedSummary.title, "Thursday, November 12")
    }

    // MARK: Everything follows the shown month

    func testMarksAndTheDaySummaryAreComputedForTheNewMonthWithoutASourceChange() throws {
        let events = StandInMonthContent(.events)
        events.content = [
            harness.date(2026, 11, 1, hour: 0): MonthKindDay(mark: .filled, phrase: "1 event", rows: [row("Parade")]),
            harness.date(2026, 11, 9, hour: 0): MonthKindDay(mark: .filled, phrase: "2 events", rows: [row("Offsite"), row("Dinner")]),
        ]
        let model = harness.makeModel(sources: [events])
        XCTAssertEqual(try day(6, in: model).marks, [.empty, .empty, .empty, .empty])

        model.showNextMonth()

        XCTAssertEqual(events.requests.last, (1...30).map { harness.date(2026, 11, $0, hour: 0) })
        XCTAssertEqual(try day(1, in: model).marks, [.filled, .empty, .empty, .empty])
        XCTAssertEqual(try day(9, in: model).accessibilityLabel, "Monday, November 9, 2 events")
        model.select(harness.date(2026, 11, 9))
        XCTAssertEqual(model.selectedSummary.sections.first?.rows.map(\.text), ["Offsite", "Dinner"])
    }

    func testMarksFromThePreviousMonthDoNotLinger() throws {
        let tasks = StandInMonthContent(.tasks)
        tasks.content = [harness.date(2026, 10, 2, hour: 0): MonthKindDay(mark: .filled, phrase: "1 task completed", rows: [row("Pay rent")])]
        let model = harness.makeModel(sources: [tasks])
        XCTAssertEqual(try day(2, in: model).marks, [.empty, .filled, .empty, .empty])

        model.showNextMonth()

        XCTAssertTrue(model.weeks.flatMap(\.cells).compactMap(\.day).allSatisfy { $0.marks == [.empty, .empty, .empty, .empty] })
    }

    func testAMonthAfterTodayShowsOnlyEvents() throws {
        let everything = MonthKindDay(mark: .filled, phrase: "1 thing", rows: [row("A thing")])
        let day1 = harness.date(2026, 11, 1, hour: 0)
        let model = harness.makeModel(sources: MonthKind.allCases.map { kind -> StandInMonthContent in
            let source = StandInMonthContent(kind)
            source.content = [day1: everything]
            return source
        })

        model.showNextMonth()

        XCTAssertEqual(try day(1, in: model).marks, [.filled, .empty, .empty, .empty])
        XCTAssertEqual(model.selectedSummary.sections.map(\.kind), [.events])
    }

    func testAPastMonthShowsEveryKind() throws {
        let everything = MonthKindDay(mark: .filled, phrase: "1 thing", rows: [row("A thing")])
        let day1 = harness.date(2026, 9, 1, hour: 0)
        let model = harness.makeModel(sources: MonthKind.allCases.map { kind -> StandInMonthContent in
            let source = StandInMonthContent(kind)
            source.content = [day1: everything]
            return source
        })

        model.showPreviousMonth()

        XCTAssertEqual(try day(1, in: model).marks, [.filled, .filled, .filled, .filled])
        XCTAssertEqual(model.selectedSummary.sections.map(\.kind), MonthKind.allCases)
    }

    // MARK: Day rollover

    func testTheTodayHighlightMovesAtMidnightAndTheSelectionStays() async throws {
        harness.setNow(harness.date(2026, 10, 6, hour: 22))
        let sleeps = MonthSleepRecorder()
        let model = harness.makeModel(sleep: { seconds in try await sleeps.sleep(seconds) })
        model.select(harness.date(2026, 10, 20))
        let loop = Task { await model.refreshAtEachDayBoundary() }
        defer { loop.cancel() }
        await eventually("the first sleep") { sleeps.durations.count == 1 }
        XCTAssertEqual(todayNumbers(in: model), [6])
        XCTAssertEqual(sleeps.durations, [2 * 3600], "it sleeps until the next local midnight")

        harness.setNow(harness.date(2026, 10, 7, hour: 0))
        sleeps.wake()

        await eventually("the new day") { self.todayNumbers(in: model) == [7] }
        XCTAssertEqual(selectedNumbers(in: model), [20])
        XCTAssertTrue(model.isShowingCurrentMonth)
        XCTAssertEqual(model.headerText, "October 2026")
    }

    func testTheSelectionStaysOnTodayWhenTheUserLeftItThere() async {
        harness.setNow(harness.date(2026, 10, 6, hour: 23))
        let sleeps = MonthSleepRecorder()
        let model = harness.makeModel(sleep: { seconds in try await sleeps.sleep(seconds) })
        let loop = Task { await model.refreshAtEachDayBoundary() }
        defer { loop.cancel() }
        await eventually("the first sleep") { sleeps.durations.count == 1 }

        harness.setNow(harness.date(2026, 10, 7, hour: 0))
        sleeps.wake()

        await eventually("the new day") { self.todayNumbers(in: model) == [7] }
        XCTAssertEqual(selectedNumbers(in: model), [6], "yesterday stays selected")
    }

    func testRolloverIntoTheNextMonthKeepsTheShownMonthAndRevealsJumpBack() async throws {
        harness.setNow(harness.date(2026, 10, 31, hour: 23))
        let sleeps = MonthSleepRecorder()
        let model = harness.makeModel(sleep: { seconds in try await sleeps.sleep(seconds) })
        model.select(harness.date(2026, 10, 12))
        let loop = Task { await model.refreshAtEachDayBoundary() }
        defer { loop.cancel() }
        await eventually("the first sleep") { sleeps.durations.count == 1 }
        XCTAssertTrue(model.isShowingCurrentMonth)

        harness.setNow(harness.date(2026, 11, 1, hour: 0))
        sleeps.wake()

        await eventually("the new day") { !model.isShowingCurrentMonth }
        XCTAssertEqual(model.headerText, "October 2026")
        XCTAssertEqual(todayNumbers(in: model), [], "the new Today is in the next month")
        XCTAssertEqual(selectedNumbers(in: model), [12])

        model.showNextMonth()
        XCTAssertEqual(todayNumbers(in: model), [1])
        XCTAssertTrue(model.isShowingCurrentMonth)
    }

    func testJumpingBackAfterARolloverSelectsTheNewToday() async throws {
        harness.setNow(harness.date(2026, 10, 31, hour: 23))
        let sleeps = MonthSleepRecorder()
        let model = harness.makeModel(sleep: { seconds in try await sleeps.sleep(seconds) })
        let loop = Task { await model.refreshAtEachDayBoundary() }
        defer { loop.cancel() }
        await eventually("the first sleep") { sleeps.durations.count == 1 }
        harness.setNow(harness.date(2026, 11, 1, hour: 0))
        sleeps.wake()
        await eventually("the new day") { !model.isShowingCurrentMonth }

        model.showCurrentMonth()

        XCTAssertEqual(model.headerText, "November 2026")
        XCTAssertEqual(selectedNumbers(in: model), [1])
        XCTAssertEqual(todayNumbers(in: model), [1])
    }

    func testRolloverRecomputesWhichDaysCanHoldTasksAndMemos() async throws {
        harness.setNow(harness.date(2026, 10, 6, hour: 23))
        let tasks = StandInMonthContent(.tasks)
        tasks.content = [harness.date(2026, 10, 7, hour: 0): MonthKindDay(mark: .filled, phrase: "1 task completed", rows: [row("Pay rent")])]
        let sleeps = MonthSleepRecorder()
        let model = harness.makeModel(sources: [tasks], sleep: { seconds in try await sleeps.sleep(seconds) })
        XCTAssertEqual(try day(7, in: model).marks, [.empty, .empty, .empty, .empty], "tomorrow can't hold tasks")
        let loop = Task { await model.refreshAtEachDayBoundary() }
        defer { loop.cancel() }
        await eventually("the first sleep") { sleeps.durations.count == 1 }

        harness.setNow(harness.date(2026, 10, 7, hour: 0))
        sleeps.wake()

        await eventually("the new day") { (try? self.day(7, in: model).marks) == [.empty, .filled, .empty, .empty] }
    }
}
