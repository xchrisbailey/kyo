import XCTest

/// The Month grid as the model reports it. October 2026 starts on a Thursday and has 31 days;
/// May 2026 starts on a Friday and has 31 days; February 2026 starts on a Sunday and has 28.
@MainActor
final class MonthGridBehaviorTests: XCTestCase {
    private let sunday = 1
    private let monday = 2

    /// Each week as day numbers, with `nil` for a blank cell.
    private func layout(_ model: MonthModel) -> [[Int?]] {
        model.weeks.map { week in week.cells.map { $0.day?.number } }
    }

    func testOpensOnTheCurrentMonthWithItsHeader() {
        let harness = MonthHarness(2026, 10, 6)
        let model = harness.makeModel()

        XCTAssertEqual(model.headerText, "October 2026")
    }

    func testSundayStartMonthLaysOutFiveWeeksWithBlanksAroundTheDays() {
        let harness = MonthHarness(2026, 10, 6, firstWeekday: sunday)
        let model = harness.makeModel()

        XCTAssertEqual(model.weekdayTitles, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        XCTAssertEqual(layout(model), [
            [nil, nil, nil, nil, 1, 2, 3],
            [4, 5, 6, 7, 8, 9, 10],
            [11, 12, 13, 14, 15, 16, 17],
            [18, 19, 20, 21, 22, 23, 24],
            [25, 26, 27, 28, 29, 30, 31],
        ])
    }

    func testMondayStartMonthLaysOutFiveWeeksWithBlanksAroundTheDays() {
        let harness = MonthHarness(2026, 10, 6, firstWeekday: monday)
        let model = harness.makeModel()

        XCTAssertEqual(model.weekdayTitles, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(layout(model), [
            [nil, nil, nil, 1, 2, 3, 4],
            [5, 6, 7, 8, 9, 10, 11],
            [12, 13, 14, 15, 16, 17, 18],
            [19, 20, 21, 22, 23, 24, 25],
            [26, 27, 28, 29, 30, 31, nil],
        ])
    }

    func testTheSameMonthSpansSixWeeksWhenTheWeekStartsOnSunday() {
        let harness = MonthHarness(2026, 5, 10, firstWeekday: sunday)
        let model = harness.makeModel()

        XCTAssertEqual(layout(model), [
            [nil, nil, nil, nil, nil, 1, 2],
            [3, 4, 5, 6, 7, 8, 9],
            [10, 11, 12, 13, 14, 15, 16],
            [17, 18, 19, 20, 21, 22, 23],
            [24, 25, 26, 27, 28, 29, 30],
            [31, nil, nil, nil, nil, nil, nil],
        ])
    }

    func testTheSameMonthSpansFiveWeeksWhenTheWeekStartsOnMonday() {
        let harness = MonthHarness(2026, 5, 10, firstWeekday: monday)
        let model = harness.makeModel()

        XCTAssertEqual(model.weeks.count, 5)
        XCTAssertEqual(layout(model).first, [nil, nil, nil, nil, 1, 2, 3])
        XCTAssertEqual(layout(model).last, [25, 26, 27, 28, 29, 30, 31])
    }

    func testAFourWeekMonthHasNoBlankWeeks() {
        let harness = MonthHarness(2026, 2, 14, firstWeekday: sunday)
        let model = harness.makeModel()

        XCTAssertEqual(model.headerText, "February 2026")
        XCTAssertEqual(model.weeks.count, 4)
        XCTAssertTrue(layout(model).allSatisfy { week in week.allSatisfy { $0 != nil } })
    }

    func testEveryWeekHasSevenCellsAndOnlyTheMonthsDaysCanBeSelected() {
        let harness = MonthHarness(2026, 10, 6)
        let model = harness.makeModel()

        XCTAssertTrue(model.weeks.allSatisfy { $0.cells.count == 7 })
        let days = model.weeks.flatMap(\.cells).compactMap(\.day)
        XCTAssertEqual(days.map(\.number), Array(1...31))
    }

    // MARK: Today

    func testTodayIsTheOnlyHighlightedDayAndStartsSelected() {
        let harness = MonthHarness(2026, 10, 6)
        let model = harness.makeModel()

        let days = model.weeks.flatMap(\.cells).compactMap(\.day)
        XCTAssertEqual(days.filter(\.isToday).map(\.number), [6])
        XCTAssertEqual(days.filter(\.isSelected).map(\.number), [6])
    }

    func testTodayIsTheDayOfTheClockNotItsTimeOfDay() {
        let harness = MonthHarness(2026, 10, 6, hour: 23)
        let model = harness.makeModel()

        let days = model.weeks.flatMap(\.cells).compactMap(\.day)
        XCTAssertEqual(days.filter(\.isToday).map(\.number), [6])
    }

    // MARK: Selection

    func testSelectingADayMovesTheSelectionAndLeavesTodayWhereItIs() {
        let harness = MonthHarness(2026, 10, 6)
        let model = harness.makeModel()

        model.select(harness.date(2026, 10, 20))

        let days = model.weeks.flatMap(\.cells).compactMap(\.day)
        XCTAssertEqual(days.filter(\.isSelected).map(\.number), [20])
        XCTAssertEqual(days.filter(\.isToday).map(\.number), [6])
    }

    func testTheDaySummaryIsHeadedByTheSelectedDaysDate() {
        let harness = MonthHarness(2026, 10, 6)
        let model = harness.makeModel()
        XCTAssertEqual(model.selectedSummary.title, "Tuesday, October 6")

        model.select(harness.date(2026, 10, 20))

        XCTAssertEqual(model.selectedSummary.title, "Tuesday, October 20")
        XCTAssertEqual(model.selectedSummary.accessibilityTitle, "Tuesday, October 20, 2026")
    }

    func testADayOutsideTheShownMonthCannotBeSelected() {
        let harness = MonthHarness(2026, 10, 6)
        let model = harness.makeModel()

        model.select(harness.date(2026, 9, 30))
        model.select(harness.date(2026, 11, 1))

        let days = model.weeks.flatMap(\.cells).compactMap(\.day)
        XCTAssertEqual(days.filter(\.isSelected).map(\.number), [6])
        XCTAssertEqual(model.selectedSummary.title, "Tuesday, October 6")
    }

    func testBlankCellsCarryNoDay() {
        let harness = MonthHarness(2026, 10, 6)
        let model = harness.makeModel()

        let blanks = model.weeks.flatMap(\.cells).filter { $0.day == nil }
        XCTAssertEqual(blanks.count, 4)
    }

    func testShowingTheCurrentMonthAgainSelectsTodayAgain() {
        let harness = MonthHarness(2026, 10, 6)
        let model = harness.makeModel()
        model.select(harness.date(2026, 10, 20))

        model.showCurrentMonth()

        let days = model.weeks.flatMap(\.cells).compactMap(\.day)
        XCTAssertEqual(days.filter(\.isSelected).map(\.number), [6])
        XCTAssertEqual(model.headerText, "October 2026")
    }
}
