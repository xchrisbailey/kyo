import SwiftData
import XCTest

/// The manager's order, seen through the habit list. September 2026 starts on a Tuesday.
@MainActor
final class HabitOrderBehaviorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private func makeList(container: ModelContainer) throws -> HabitListStore {
        HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: container,
            now: { self.now }, calendar: calendar
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try HabitStorage.makeContainer()
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HabitOrderBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func names(_ list: HabitListStore) -> [String] { list.habits.map(\.name) }

    private func makeABCD(_ list: HabitListStore) {
        for name in ["A", "B", "C", "D"] { list.addHabit(name: name) }
    }

    func testMovingHabitsFollowsOnMoveOffsetSemantics() throws {
        let list = try makeList(container: try makeContainer())
        makeABCD(list)

        list.moveHabits(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(names(list), ["B", "C", "A", "D"])

        list.moveHabits(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(names(list), ["D", "B", "C", "A"])

        list.moveHabits(fromOffsets: IndexSet(integer: 1), toOffset: 4)
        XCTAssertEqual(names(list), ["D", "C", "A", "B"])

        list.moveHabits(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(names(list), ["C", "B", "D", "A"])
    }

    func testMovingRewritesOrderValuesContiguously() throws {
        let list = try makeList(container: try makeContainer())
        makeABCD(list)

        list.moveHabits(fromOffsets: IndexSet(integer: 3), toOffset: 1)

        XCTAssertEqual(names(list), ["A", "D", "B", "C"])
        XCTAssertEqual(list.habits.map(\.order), [0, 1, 2, 3])
    }

    func testMovingToTheSamePlaceOrOutOfRangeChangesNothing() throws {
        let list = try makeList(container: try makeContainer())
        makeABCD(list)
        let before = list.habits

        list.moveHabits(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        list.moveHabits(fromOffsets: IndexSet(integer: 1), toOffset: 2)
        list.moveHabits(fromOffsets: IndexSet(integer: 9), toOffset: 0)
        list.moveHabits(fromOffsets: IndexSet(integer: 0), toOffset: 9)
        list.moveHabits(fromOffsets: IndexSet(), toOffset: 0)

        XCTAssertEqual(list.habits, before)
    }

    func testTheOrderPersistsAcrossReopening() throws {
        let container = try makeContainer()
        let list = try makeList(container: container)
        makeABCD(list)
        list.moveHabits(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        let reopened = try makeList(container: container)

        XCTAssertEqual(names(reopened), ["C", "A", "B", "D"])
        XCTAssertEqual(reopened.todayHabits.map(\.habit.name), ["C", "A", "B", "D"])
    }

    func testTodayFollowsTheManagerOrderWithinEachGroup() throws {
        let list = try makeList(container: try makeContainer())
        makeABCD(list)
        let ids = Dictionary(uniqueKeysWithValues: list.habits.map { ($0.name, $0.id) })
        _ = list.toggleCheckOff(id: try XCTUnwrap(ids["B"]))
        _ = list.toggleCheckOff(id: try XCTUnwrap(ids["D"]))
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["A", "C", "B", "D"])

        list.moveHabits(fromOffsets: IndexSet(integer: 3), toOffset: 0)   // D A B C
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["A", "C", "D", "B"])

        list.moveHabits(fromOffsets: IndexSet(integer: 2), toOffset: 0)   // B D A C
        XCTAssertEqual(names(list), ["B", "D", "A", "C"])
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["A", "C", "B", "D"])
        XCTAssertEqual(list.todayHabits.map(\.isDone), [false, false, true, true])
    }

    func testNewHabitsGoToTheEndAfterAReorder() throws {
        let container = try makeContainer()
        let list = try makeList(container: container)
        makeABCD(list)
        list.moveHabits(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        let added = try XCTUnwrap(list.addHabit(name: "E"))

        XCTAssertEqual(names(list), ["D", "A", "B", "C", "E"])
        XCTAssertEqual(added.order, 4)
        XCTAssertEqual(try makeList(container: container).habits.map(\.name), ["D", "A", "B", "C", "E"])
    }

    func testReorderingKeepsLogsSchedulesAndDeletionStillWorks() throws {
        let list = try makeList(container: try makeContainer())
        let a = try XCTUnwrap(list.addHabit(name: "A", schedule: .weeklyTarget(3)))
        _ = list.addHabit(name: "B")
        _ = list.toggleCheckOff(id: a.id)

        list.moveHabits(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        let moved = try XCTUnwrap(list.habits.first { $0.id == a.id })
        XCTAssertEqual(moved.schedule, .weeklyTarget(3))
        XCTAssertEqual(moved.checkOffs.count, 1)
        list.deleteHabit(id: a.id)
        XCTAssertEqual(names(list), ["B"])
    }

    func testScheduleSummaries() {
        var monday = calendar
        monday.firstWeekday = 2
        XCTAssertEqual(HabitSchedule.everyDay.summary(calendar: calendar), "Every day")
        XCTAssertEqual(HabitSchedule.weeklyTarget(3).summary(calendar: calendar), "3× a week")
        // Weekday numbers: 1 = Sunday ... 7 = Saturday; shown in the calendar's week order.
        let days: Set<Int> = [2, 4, 6, 1]
        XCTAssertEqual(HabitSchedule.weekdays(days).summary(calendar: calendar), "Sun Mon Wed Fri")
        XCTAssertEqual(HabitSchedule.weekdays(days).summary(calendar: monday), "Mon Wed Fri Sun")
    }
}
