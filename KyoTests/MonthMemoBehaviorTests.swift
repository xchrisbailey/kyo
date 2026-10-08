import SwiftData
import XCTest

/// Memos in Month, seen through the Month model on a real memo store with in-memory storage.
/// Today is Tuesday 6 October 2026 unless a test moves the clock.
@MainActor
final class MonthMemoBehaviorTests: MonthTestCase {
    private let harness = MonthHarness(2026, 10, 6)

    private struct Fixture {
        let store: MemoStore
        let model: MonthModel
    }

    private func makeFixture() throws -> Fixture {
        let container = try KyoModelContainer.make(inMemory: true)
        let store = MemoStore(modelContainer: container, now: { self.harness.now }, calendar: harness.calendar)
        let model = harness.makeModel(sources: [MemoMonthContent(store: store)])
        return Fixture(store: store, model: model)
    }

    /// Writes a Written memo as of `moment`, then puts the clock back and lets the store notice.
    @discardableResult
    private func write(_ text: String, on moment: Date, to store: MemoStore) throws -> Memo {
        let restored = harness.now
        harness.setNow(moment)
        let memo = try XCTUnwrap(store.addWrittenMemo(text: text))
        harness.setNow(restored)
        store.refreshForCurrentDay()
        return memo
    }

    private func memoMark(onDay number: Int, in model: MonthModel) throws -> MonthMark {
        let index = try XCTUnwrap(MonthKind.allCases.firstIndex(of: .memos))
        return try day(number, in: model).marks[index]
    }

    // MARK: Marks

    func testADayWithAMemoShowsTheMemoMarkAndADayWithNoneLeavesTheSlotEmpty() throws {
        let f = try makeFixture()
        try write("Call the dentist", on: harness.date(2026, 10, 3), to: f.store)

        XCTAssertEqual(try memoMark(onDay: 3, in: f.model), .filled)
        XCTAssertEqual(try memoMark(onDay: 4, in: f.model), .empty)
    }

    // MARK: Day summary

    private func memoRows(in model: MonthModel) -> [MonthSummaryRow] {
        model.selectedSummary.sections.first { $0.kind == .memos }?.rows ?? []
    }

    func testTheDaySummaryListsAPastDaysMemosNewestFirstEachOpeningThatMemo() throws {
        let f = try makeFixture()
        let earlier = try write("Pack the tent", on: harness.date(2026, 10, 3, hour: 9), to: f.store)
        let later = try write("Dentist at ten\nBring the forms", on: harness.date(2026, 10, 3, hour: 17), to: f.store)
        try write("Another day", on: harness.date(2026, 10, 2), to: f.store)

        f.model.select(harness.date(2026, 10, 3))

        let rows = memoRows(in: f.model)
        XCTAssertEqual(rows.map(\.text), ["Dentist at ten", "Pack the tent"])
        XCTAssertEqual(rows.map(\.target), [.memo(later.id), .memo(earlier.id)])
        XCTAssertFalse(f.model.selectedSummary.isEmpty, "a day with memos isn't \"Nothing on this day\"")
    }

    func testTodaysDaySummaryListsTodaysMemos() throws {
        let f = try makeFixture()
        let memo = try write("Idea for the weekend", on: harness.date(2026, 10, 6, hour: 8), to: f.store)

        XCTAssertEqual(memoRows(in: f.model).map(\.target), [.memo(memo.id)])
        XCTAssertEqual(try memoMark(onDay: 6, in: f.model), .filled)
    }

    func testTheDayCellReadsItsMemoCount() throws {
        let f = try makeFixture()
        try write("One", on: harness.date(2026, 10, 3, hour: 9), to: f.store)
        try write("Two", on: harness.date(2026, 10, 4, hour: 9), to: f.store)
        try write("Three", on: harness.date(2026, 10, 4, hour: 10), to: f.store)

        XCTAssertEqual(try day(3, in: f.model).accessibilityLabel, "Saturday, October 3, 1 memo")
        XCTAssertEqual(try day(4, in: f.model).accessibilityLabel, "Sunday, October 4, 2 memos")
        XCTAssertEqual(try day(5, in: f.model).accessibilityLabel, "Monday, October 5")
    }

    // MARK: Recomputing

    func testMonthUpdatesWhenAMemoIsAddedEditedAndDeleted() throws {
        let f = try makeFixture()
        XCTAssertEqual(try memoMark(onDay: 6, in: f.model), .empty)
        XCTAssertEqual(f.model.selectedSummary.sections, [])

        let memo = try XCTUnwrap(f.store.addWrittenMemo(text: "Buy stamps"))
        XCTAssertEqual(try memoMark(onDay: 6, in: f.model), .filled)
        XCTAssertEqual(memoRows(in: f.model).map(\.text), ["Buy stamps"])

        f.store.editMemo(id: memo.id, text: "Buy stamps and envelopes")
        XCTAssertEqual(memoRows(in: f.model).map(\.text), ["Buy stamps and envelopes"])

        f.store.deleteMemo(id: memo.id)
        XCTAssertEqual(try memoMark(onDay: 6, in: f.model), .empty)
        XCTAssertTrue(f.model.selectedSummary.isEmpty)
    }

    func testDeletingTheOnlyMemoOnAPastDayClearsItsMark() throws {
        let f = try makeFixture()
        let memo = try write("Old thought", on: harness.date(2026, 10, 1), to: f.store)
        XCTAssertEqual(try memoMark(onDay: 1, in: f.model), .filled)

        f.store.deleteMemo(id: memo.id)

        XCTAssertEqual(try memoMark(onDay: 1, in: f.model), .empty)
    }

    // MARK: Other months

    func testAnotherMonthShowsItsOwnMemoMarksAndRowsStraightAway() throws {
        let f = try makeFixture()
        let memo = try write("From September", on: harness.date(2026, 9, 12), to: f.store)

        f.model.showPreviousMonth()

        XCTAssertEqual(try memoMark(onDay: 12, in: f.model), .filled)
        XCTAssertEqual(try memoMark(onDay: 13, in: f.model), .empty)
        f.model.select(harness.date(2026, 9, 12))
        XCTAssertEqual(memoRows(in: f.model).map(\.target), [.memo(memo.id)])

        f.model.showCurrentMonth()
        XCTAssertEqual(try memoMark(onDay: 12, in: f.model), .empty)
    }

    // MARK: Days after Today

    func testAMemoRecordedAgainstALaterDayShowsNeitherMarkNorRow() throws {
        let f = try makeFixture()
        // Written while the clock was ahead, as after a time zone change.
        try write("From the future", on: harness.date(2026, 10, 9), to: f.store)

        XCTAssertEqual(try memoMark(onDay: 9, in: f.model), .empty)
        f.model.select(harness.date(2026, 10, 9))
        XCTAssertEqual(memoRows(in: f.model), [])
        XCTAssertTrue(f.model.selectedSummary.isEmpty)

        // Once that day is Today it shows.
        harness.setNow(harness.date(2026, 10, 9))
        f.model.refresh()
        XCTAssertEqual(try memoMark(onDay: 9, in: f.model), .filled)
    }
}
