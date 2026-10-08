import SwiftData
import XCTest

/// Memos in Month, seen through the Month model on a real memo store with in-memory storage.
/// Today is Tuesday 6 October 2026 unless a test moves the clock.
@MainActor
final class MonthMemoBehaviorTests: XCTestCase {
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

    /// Writes a Written memo as of `moment`, then puts the clock back.
    @discardableResult
    private func write(_ text: String, on moment: Date, to store: MemoStore) throws -> Memo {
        let restored = harness.now
        harness.setNow(moment)
        defer { harness.setNow(restored) }
        return try XCTUnwrap(store.addWrittenMemo(text: text))
    }

    private func day(_ number: Int, in model: MonthModel) throws -> MonthDay {
        try XCTUnwrap(model.weeks.flatMap(\.cells).compactMap(\.day).first { $0.number == number })
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
}
