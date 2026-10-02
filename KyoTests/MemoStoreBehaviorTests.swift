import SwiftData
import XCTest

/// Behavior of **Written memos** through `MemoStoreBehavior`, on an in-memory store with a
/// controllable clock and calendar.
@MainActor
final class MemoStoreBehaviorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// September 2026, UTC.
    private func moment(_ day: Int, _ hour: Int = 9, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    private func makeContainer() throws -> ModelContainer {
        try KyoModelContainer.make(inMemory: true)
    }

    private func makeStore(_ container: ModelContainer, at now: Date? = nil) throws -> MemoStore {
        let clock = try now ?? moment(29)
        return MemoStore(modelContainer: container, now: { clock }, calendar: calendar)
    }

    // MARK: Adding

    func testAddingAWrittenMemoShowsItOnTodayWithItsTitleAndDetail() throws {
        let store: any MemoStoreBehavior = try makeStore(try makeContainer(), at: try moment(29, 9, 41))

        let memo = try XCTUnwrap(store.addWrittenMemo(text: "An idea for the weekend\nTry the trail by the lake.\nBring coffee."))

        XCTAssertEqual(store.memos, [memo])
        XCTAssertEqual(memo.kind, .written)
        XCTAssertEqual(memo.title, "An idea for the weekend")
        XCTAssertEqual(memo.detail, "Try the trail by the lake. Bring coffee.")
        XCTAssertEqual(memo.createdAt, try moment(29, 9, 41))
    }

    func testTheFirstLineIsTheTitleEvenAfterBlankLinesAndWhitespace() throws {
        let store = try makeStore(try makeContainer())

        let memo = try XCTUnwrap(store.addWrittenMemo(text: "\n  Groceries  \n\nEggs"))

        XCTAssertEqual(memo.title, "Groceries")
        XCTAssertEqual(memo.detail, "Eggs")
    }

    func testAMemoWithOneLineHasNoDetail() throws {
        let store = try makeStore(try makeContainer())

        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Just a title"))

        XCTAssertEqual(memo.title, "Just a title")
        XCTAssertNil(memo.detail)
    }

    func testSavingAMemoWithNoTextDiscardsIt() throws {
        let container = try makeContainer()
        let store = try makeStore(container)

        XCTAssertNil(store.addWrittenMemo(text: ""))
        XCTAssertNil(store.addWrittenMemo(text: " \n\t "))

        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 0)
    }

    // MARK: Section subtitle

    func testTheSubtitleCountsTodaysMemosAndFallsBackWhenThereAreNone() throws {
        let store = try makeStore(try makeContainer())
        XCTAssertEqual(store.sectionSubtitle, "Notes & voice")

        let first = try XCTUnwrap(store.addWrittenMemo(text: "One"))
        XCTAssertEqual(store.sectionSubtitle, "1 memo")

        _ = store.addWrittenMemo(text: "Two")
        XCTAssertEqual(store.sectionSubtitle, "2 memos")

        _ = store.deleteMemo(id: first.id)
        XCTAssertEqual(store.sectionSubtitle, "1 memo")
    }

    // MARK: Ordering

    func testMemosAreListedNewestFirst() throws {
        var now = try moment(29, 8)
        let store = MemoStore(modelContainer: try makeContainer(), now: { now }, calendar: calendar)

        _ = store.addWrittenMemo(text: "Morning")
        now = try moment(29, 12)
        _ = store.addWrittenMemo(text: "Noon")
        now = try moment(29, 17)
        _ = store.addWrittenMemo(text: "Evening")

        XCTAssertEqual(store.memos.map(\.title), ["Evening", "Noon", "Morning"])
    }

    func testEditingAMemoKeepsItsPlaceInTheOrder() throws {
        var now = try moment(29, 8)
        let store = MemoStore(modelContainer: try makeContainer(), now: { now }, calendar: calendar)
        let first = try XCTUnwrap(store.addWrittenMemo(text: "First"))
        now = try moment(29, 9)
        _ = store.addWrittenMemo(text: "Second")

        now = try moment(29, 20)
        _ = store.editMemo(id: first.id, text: "First, revised")

        XCTAssertEqual(store.memos.map(\.title), ["Second", "First, revised"])
        XCTAssertEqual(store.memos.last?.createdAt, try moment(29, 8))
    }

    // MARK: Editing

    func testEditsAreSavedImmediatelyAndKeepTheMemosIdentityTimeAndDay() throws {
        let container = try makeContainer()
        let store = try makeStore(container, at: try moment(29, 9, 41))
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Draft"))

        let edited = try XCTUnwrap(store.editMemo(id: memo.id, text: "Final title\nWith detail"))

        XCTAssertEqual(edited.id, memo.id)
        XCTAssertEqual(edited.createdAt, memo.createdAt)
        XCTAssertEqual(edited.day, memo.day)
        XCTAssertEqual(edited.title, "Final title")
        XCTAssertEqual(edited.detail, "With detail")
        XCTAssertEqual(store.memos, [edited])
        // No close or save step: a store opened on the same container already sees it.
        XCTAssertEqual(try makeStore(container, at: try moment(29, 9, 41)).memos, [edited])
    }

    func testEditingKeepsTheTextAsTyped() throws {
        let store = try makeStore(try makeContainer())
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Note"))

        let edited = try XCTUnwrap(store.editMemo(id: memo.id, text: "Note \n"))

        XCTAssertEqual(edited.text, "Note \n")
    }

    func testEditingAnUnknownMemoDoesNothing() throws {
        let store = try makeStore(try makeContainer())
        _ = store.addWrittenMemo(text: "Keep")

        XCTAssertNil(store.editMemo(id: UUID(), text: "Other"))
        XCTAssertEqual(store.memos.map(\.title), ["Keep"])
    }

    func testEmptyingTheTextKeepsTheMemoUntilItIsClosedThenDiscardsIt() throws {
        let store = try makeStore(try makeContainer())
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Something"))

        _ = store.editMemo(id: memo.id, text: "")
        XCTAssertEqual(store.memos.count, 1)

        let discarded = store.closeMemo(id: memo.id)

        XCTAssertEqual(discarded?.id, memo.id)
        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertNil(store.memo(id: memo.id))
    }

    func testClosingAMemoWithTextKeepsIt() throws {
        let store = try makeStore(try makeContainer())
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Keep me"))
        _ = store.editMemo(id: memo.id, text: "Keep me, edited")

        XCTAssertNil(store.closeMemo(id: memo.id))
        XCTAssertEqual(store.memos.map(\.title), ["Keep me, edited"])
    }

    func testRetypingTextBeforeClosingKeepsTheMemo() throws {
        let store = try makeStore(try makeContainer())
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Something"))

        _ = store.editMemo(id: memo.id, text: "  \n ")
        _ = store.editMemo(id: memo.id, text: "Something else")

        XCTAssertNil(store.closeMemo(id: memo.id))
        XCTAssertEqual(store.memos.map(\.title), ["Something else"])
    }

    func testAMemoLeftEmptyByAQuitIsDiscardedOnTheNextLaunch() throws {
        let container = try makeContainer()
        let store = try makeStore(container)
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Something"))
        _ = store.editMemo(id: memo.id, text: "")

        let relaunched = try makeStore(container)

        XCTAssertTrue(relaunched.memos.isEmpty)
        XCTAssertNil(relaunched.memo(id: memo.id))
    }

    // MARK: Deleting

    func testDeletingAMemoIsPermanent() throws {
        let container = try makeContainer()
        let store = try makeStore(container)
        let kept = try XCTUnwrap(store.addWrittenMemo(text: "Kept"))
        let removed = try XCTUnwrap(store.addWrittenMemo(text: "Removed"))

        let result = store.deleteMemo(id: removed.id)

        XCTAssertEqual(result, removed)
        XCTAssertEqual(store.memos, [kept])
        XCTAssertNil(store.memo(id: removed.id))
        XCTAssertEqual(try makeStore(container).memos, [kept])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 1)
    }

    func testDeletingAnUnknownMemoDoesNothing() throws {
        let store = try makeStore(try makeContainer())
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Keep"))

        XCTAssertNil(store.deleteMemo(id: UUID()))
        XCTAssertEqual(store.memos, [memo])
    }

    // MARK: A memo's day

    func testTodayShowsOnlyMemosWhoseDayIsToday() throws {
        let container = try makeContainer()
        var now = try moment(28, 23, 59)
        let store = MemoStore(modelContainer: container, now: { now }, calendar: calendar)
        let yesterday = try XCTUnwrap(store.addWrittenMemo(text: "Late last night"))
        XCTAssertEqual(store.memos, [yesterday])

        now = try moment(29, 0, 1)
        store.refreshForCurrentDay()
        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertEqual(store.sectionSubtitle, "Notes & voice")

        let today = try XCTUnwrap(store.addWrittenMemo(text: "Just after midnight"))

        XCTAssertEqual(store.memos, [today])
        XCTAssertEqual(today.day, TaskCompletionDay(era: 1, year: 2026, month: 9, day: 29))
        XCTAssertEqual(yesterday.day, TaskCompletionDay(era: 1, year: 2026, month: 9, day: 28))
        XCTAssertEqual(store.memo(id: yesterday.id), yesterday)
        XCTAssertEqual(MemoStore(modelContainer: container, now: { now }, calendar: calendar).memos, [today])
    }

    func testAMemoEditedAfterMidnightStaysOnItsOwnDay() throws {
        var now = try moment(28, 23, 58)
        let store = MemoStore(modelContainer: try makeContainer(), now: { now }, calendar: calendar)
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Before midnight"))

        now = try moment(29, 0, 5)
        let edited = try XCTUnwrap(store.editMemo(id: memo.id, text: "Edited after midnight"))

        XCTAssertEqual(edited.day, memo.day)
        XCTAssertEqual(edited.createdAt, memo.createdAt)
        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertEqual(store.memo(id: memo.id)?.text, "Edited after midnight")
    }

    func testAMemoDoesNotMoveWhenTheTimeZoneChanges() throws {
        let container = try makeContainer()
        var newYork = calendar
        newYork.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        // 23:30 on Sep 28 in New York is 03:30 on Sep 29 in UTC.
        let instant = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 23, minute: 30)))
        let atHome = MemoStore(modelContainer: container, now: { instant }, calendar: newYork)
        let memo = try XCTUnwrap(atHome.addWrittenMemo(text: "Written at home"))
        XCTAssertEqual(memo.day, TaskCompletionDay(era: 1, year: 2026, month: 9, day: 28))

        let travelling = MemoStore(modelContainer: container, now: { instant }, calendar: calendar)

        XCTAssertEqual(travelling.memo(id: memo.id)?.day, memo.day)
        XCTAssertTrue(travelling.memos.isEmpty)
        let there = try XCTUnwrap(travelling.addWrittenMemo(text: "Written abroad"))
        XCTAssertEqual(there.day, TaskCompletionDay(era: 1, year: 2026, month: 9, day: 29))
        XCTAssertEqual(travelling.memos, [there])
        XCTAssertEqual(MemoStore(modelContainer: container, now: { instant }, calendar: newYork).memos, [memo])
    }

    // MARK: Persistence

    func testMemosPersistAcrossReopening() throws {
        let container = try makeContainer()
        var now = try moment(29, 8)
        let store = MemoStore(modelContainer: container, now: { now }, calendar: calendar)
        _ = store.addWrittenMemo(text: "Morning\nDetail")
        now = try moment(29, 10)
        let second = try XCTUnwrap(store.addWrittenMemo(text: "Mid-morning"))
        _ = store.editMemo(id: second.id, text: "Mid-morning, edited")
        let removed = try XCTUnwrap(store.addWrittenMemo(text: "Removed"))
        _ = store.deleteMemo(id: removed.id)

        let reopened = MemoStore(modelContainer: container, now: { now }, calendar: calendar)

        XCTAssertEqual(reopened.memos, store.memos)
        XCTAssertEqual(reopened.memos.map(\.title), ["Mid-morning, edited", "Morning"])
        XCTAssertEqual(reopened.sectionSubtitle, "2 memos")
    }

    func testMemosAreStoredApartFromTasksAndHabitsInTheSameContainer() throws {
        let container = try makeContainer()
        _ = try makeStore(container).addWrittenMemo(text: "A memo")
        _ = TaskListStore(modelContainer: container).addTask(text: "A task")

        XCTAssertEqual(try makeStore(container).memos.map(\.title), ["A memo"])
        XCTAssertEqual(TaskListStore(modelContainer: container).tasks.map(\.text), ["A task"])
    }

    func testMemosStoredWithTheSameIDListOnceAndDeleteTogether() throws {
        let container = try makeContainer()
        let id = UUID()
        let at = try moment(29, 9)
        let day = TaskCompletionDay(date: at, calendar: calendar)
        container.mainContext.insert(MemoRecord(id: id, kind: .written, createdAt: at, day: day, text: "Twice"))
        container.mainContext.insert(MemoRecord(id: id, kind: .written, createdAt: at, day: day, text: "Twice"))
        try container.mainContext.save()

        let store = try makeStore(container)
        XCTAssertEqual(store.memos.map(\.title), ["Twice"])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 1)

        _ = store.deleteMemo(id: id)
        XCTAssertTrue(try makeStore(container).memos.isEmpty)
    }
}
