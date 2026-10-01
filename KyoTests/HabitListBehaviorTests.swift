import XCTest

@MainActor
final class HabitListBehaviorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testAddingHabitsTrimsNameAndPreservesCreationOrder() throws {
        let list: any HabitListBehavior = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits")

        let first = try XCTUnwrap(list.addHabit(name: "  Read  "))
        let second = try XCTUnwrap(list.addHabit(name: "Walk"))

        XCTAssertEqual(list.habits.map(\.name), ["Read", "Walk"])
        XCTAssertEqual(list.habits.map(\.creationOrder), [0, 1])
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Read", "Walk"])
        XCTAssertEqual(list.todayCount, 2)
        XCTAssertEqual(list.doneCount, 0)
    }

    func testBlankNameDoesNotCreateAHabit() throws {
        let list: any HabitListBehavior = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits")

        XCTAssertNil(list.addHabit(name: " \n\t "))
        XCTAssertTrue(list.habits.isEmpty)
        XCTAssertEqual(list.todayCount, 0)
    }

    func testCheckingOffMovesHabitToDoneGroupAndUncheckingRestoresIt() throws {
        let list: any HabitListBehavior = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", now: { self.day(29) }, calendar: calendar
        )
        let first = try XCTUnwrap(list.addHabit(name: "First"))
        _ = list.addHabit(name: "Second")
        _ = list.addHabit(name: "Third")

        _ = list.toggleCheckOff(id: first.id)

        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Second", "Third", "First"])
        XCTAssertEqual(list.todayHabits.map(\.isDone), [false, false, true])
        XCTAssertEqual(list.doneCount, 1)
        XCTAssertEqual(list.todayCount, 3)

        let unchecked = try XCTUnwrap(list.toggleCheckOff(id: first.id))

        XCTAssertTrue(unchecked.checkOffs.isEmpty)
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["First", "Second", "Third"])
        XCTAssertEqual(list.doneCount, 0)
    }

    func testEachGroupKeepsManagerOrder() throws {
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", now: { self.day(29) }, calendar: calendar
        )
        let a = try XCTUnwrap(list.addHabit(name: "A"))
        _ = list.addHabit(name: "B")
        let c = try XCTUnwrap(list.addHabit(name: "C"))
        _ = list.addHabit(name: "D")

        _ = list.toggleCheckOff(id: c.id)
        _ = list.toggleCheckOff(id: a.id)

        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["B", "D", "A", "C"])
    }

    func testTogglingAnUnknownHabitDoesNothing() throws {
        let list = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits")
        XCTAssertNil(list.toggleCheckOff(id: UUID()))
    }

    func testHabitsAndCheckOffsPersistAcrossReopening() throws {
        let defaults = try makeDefaults()
        let now = day(29)
        let list = HabitListStore(userDefaults: defaults, storageKey: "habits", now: { now }, calendar: calendar)
        let first = try XCTUnwrap(list.addHabit(name: "First"))
        _ = list.addHabit(name: "Second")
        _ = list.toggleCheckOff(id: first.id)

        let reopened = HabitListStore(userDefaults: defaults, storageKey: "habits", now: { now }, calendar: calendar)

        XCTAssertEqual(reopened.habits, list.habits)
        XCTAssertEqual(reopened.todayHabits, list.todayHabits)
        XCTAssertEqual(reopened.doneCount, 1)
        let third = try XCTUnwrap(reopened.addHabit(name: "Third"))
        XCTAssertEqual(third.creationOrder, 2)
    }

    func testCheckOffsAreKeyedToTheCurrentDay() throws {
        let defaults = try makeDefaults()
        var now = day(28, hour: 21)
        let list = HabitListStore(userDefaults: defaults, storageKey: "habits", now: { now }, calendar: calendar)
        let habit = try XCTUnwrap(list.addHabit(name: "Stretch"))
        _ = list.toggleCheckOff(id: habit.id)
        XCTAssertEqual(list.doneCount, 1)

        now = day(29, hour: 8)
        list.refreshForCurrentDay()

        XCTAssertEqual(list.todayHabits.map(\.isDone), [false])
        XCTAssertEqual(list.doneCount, 0)
        XCTAssertEqual(list.todayCount, 1)

        // Checking off today adds to the log; unchecking today leaves yesterday's check-off.
        _ = list.toggleCheckOff(id: habit.id)
        XCTAssertEqual(try XCTUnwrap(list.habits.first).checkOffs.count, 2)
        _ = list.toggleCheckOff(id: habit.id)
        XCTAssertEqual(try XCTUnwrap(list.habits.first).checkOffs.count, 1)

        let reopened = HabitListStore(userDefaults: defaults, storageKey: "habits", now: { now }, calendar: calendar)
        XCTAssertEqual(reopened.doneCount, 0)
    }

    func testHabitsUseTheirOwnStorageKeyApartFromTasks() throws {
        let defaults = try makeDefaults()
        let list = HabitListStore(userDefaults: defaults)
        _ = list.addHabit(name: "Walk")

        XCTAssertNotNil(defaults.data(forKey: HabitListStore.storageKey))
        XCTAssertNotEqual(HabitListStore.storageKey, TaskListStore.storageKey)
        XCTAssertTrue(TaskListStore(userDefaults: defaults).tasks.isEmpty)
    }

    private func day(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HabitListBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
