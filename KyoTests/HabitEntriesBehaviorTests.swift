import SwiftData
import XCTest

/// Every habit with its streak, week progress and whether it is due today, seen through the habit
/// list: what the Habits sheet rows show. September 2026 starts on a Tuesday: Sundays fall on the
/// 6th, 13th and 20th; Mondays on the 7th, 14th and 21st.
@MainActor
final class HabitEntriesBehaviorTests: XCTestCase {
    private let monday = 2
    private let wednesday = 4
    private let friday = 6

    private var now = Date()
    private var calendar = Calendar(identifier: .gregorian)

    private func makeList(on start: Int, firstWeekday: Int = 1) throws -> HabitListStore {
        calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        now = sep(start)
        return HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits",
            modelContainer: try HabitStorage.makeContainer(), now: { self.now }, calendar: calendar
        )
    }

    private func sep(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 10))!
    }

    private func go(_ list: HabitListStore, to day: Int) {
        now = sep(day)
        list.refreshForCurrentDay()
    }

    /// Moves the clock to each day in turn and toggles the habit's check-off.
    private func check(_ list: HabitListStore, _ habit: Habit, on days: [Int]) {
        for day in days {
            go(list, to: day)
            _ = list.toggleCheckOff(id: habit.id)
        }
    }

    private func entry(_ list: HabitListStore, _ habit: Habit) throws -> HabitEntry {
        try XCTUnwrap(list.habitEntries.first { $0.id == habit.id })
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HabitEntriesBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: Which habits, in what order

    func testEveryHabitIsListedInHabitOrderIncludingOneNotDueToday() throws {
        let list = try makeList(on: 8) // Tuesday
        let daily = try XCTUnwrap(list.addHabit(name: "Read"))
        let wednesdays = try XCTUnwrap(list.addHabit(name: "Gym", schedule: .weekdays([wednesday])))
        let weekly = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))

        XCTAssertEqual(list.habitEntries.map(\.id), [daily.id, wednesdays.id, weekly.id])
        XCTAssertEqual(list.habitEntries.map(\.isDueToday), [true, false, true])
        XCTAssertEqual(list.todayHabits.map(\.id), [daily.id, weekly.id], "Today still lists only the due ones")
    }

    func testTheListFollowsAReorder() throws {
        let list = try makeList(on: 8)
        let first = try XCTUnwrap(list.addHabit(name: "A"))
        let second = try XCTUnwrap(list.addHabit(name: "B"))
        let third = try XCTUnwrap(list.addHabit(name: "C"))

        list.moveHabits(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(list.habitEntries.map(\.id), [third.id, first.id, second.id])
    }

    func testAnAddAnEditAndADeleteUpdateTheList() throws {
        let list = try makeList(on: 8)
        XCTAssertTrue(list.habitEntries.isEmpty)

        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        XCTAssertEqual(list.habitEntries.map(\.habit.name), ["Read"])

        _ = list.editHabit(id: habit.id, name: "Read more", schedule: .weeklyTarget(3))
        let edited = try entry(list, habit)
        XCTAssertEqual(edited.habit.name, "Read more")
        XCTAssertEqual(edited.weekProgress, HabitWeekProgress(count: 0, target: 3))

        _ = list.deleteHabit(id: habit.id)
        XCTAssertTrue(list.habitEntries.isEmpty)
    }

    // MARK: Streaks

    func testANotDueHabitShowsTheStreakItWouldShowOnADueDay() throws {
        let list = try makeList(on: 7)
        let habit = try XCTUnwrap(list.addHabit(name: "Gym", schedule: .weekdays([monday, wednesday, friday])))
        check(list, habit, on: [7, 9, 11])

        go(list, to: 12) // Saturday: not due
        XCTAssertFalse(try entry(list, habit).isDueToday)
        XCTAssertEqual(try entry(list, habit).streak, 3)

        go(list, to: 14) // Monday, still unchecked: due, and the open day doesn't break it
        XCTAssertTrue(try entry(list, habit).isDueToday)
        XCTAssertEqual(try entry(list, habit).streak, 3)

        _ = list.toggleCheckOff(id: habit.id)
        XCTAssertEqual(try entry(list, habit).streak, 4)
    }

    func testAMissedDueDayBreaksTheStreakAfterMidnight() throws {
        let list = try makeList(on: 7)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [7, 8])
        XCTAssertEqual(try entry(list, habit).streak, 2)

        go(list, to: 9) // the 9th is open: the streak stands
        XCTAssertEqual(try entry(list, habit).streak, 2)

        go(list, to: 10) // the 9th was missed
        XCTAssertEqual(try entry(list, habit).streak, 0)
    }

    // MARK: Week progress

    func testAWeeklyTargetShowsWeekProgressAndWeekStreakWhenMetAndExceeded() throws {
        let list = try makeList(on: 7, firstWeekday: 2) // weeks start on Monday
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(3)))

        check(list, habit, on: [7, 8])
        XCTAssertEqual(try entry(list, habit).weekProgress, HabitWeekProgress(count: 2, target: 3))
        XCTAssertEqual(try entry(list, habit).streak, 0, "the week in progress doesn't count yet")

        check(list, habit, on: [9])
        XCTAssertEqual(try entry(list, habit).weekProgress, HabitWeekProgress(count: 3, target: 3))
        XCTAssertEqual(try entry(list, habit).streak, 1)

        check(list, habit, on: [10])
        XCTAssertEqual(try entry(list, habit).weekProgress, HabitWeekProgress(count: 4, target: 3))
        XCTAssertEqual(try entry(list, habit).streak, 1, "check-offs past the target add nothing")

        go(list, to: 13) // Sunday: still the week of the 7th when weeks start on Monday
        XCTAssertEqual(try entry(list, habit).weekProgress, HabitWeekProgress(count: 4, target: 3))

        go(list, to: 14) // a new week: progress starts over and the week streak stands
        XCTAssertEqual(try entry(list, habit).weekProgress, HabitWeekProgress(count: 0, target: 3))
        XCTAssertEqual(try entry(list, habit).streak, 1)
    }

    func testADayBasedHabitHasNoWeekProgress() throws {
        let list = try makeList(on: 8)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))

        XCTAssertNil(try entry(list, habit).weekProgress)
    }

    // MARK: Zero values

    func testAFreshHabitReportsZeros() throws {
        let list = try makeList(on: 8)
        let daily = try XCTUnwrap(list.addHabit(name: "Read"))
        let weekly = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(3)))

        XCTAssertEqual(try entry(list, daily).streak, 0)
        XCTAssertEqual(try entry(list, weekly).streak, 0)
        XCTAssertEqual(try entry(list, weekly).weekProgress, HabitWeekProgress(count: 0, target: 3))
    }

    // MARK: Updates

    func testACheckOffOnTodayUpdatesTheEntryAtOnce() throws {
        let list = try makeList(on: 8)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        let weekly = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(3)))

        _ = list.toggleCheckOff(id: habit.id)
        _ = list.toggleCheckOff(id: weekly.id)
        XCTAssertEqual(try entry(list, habit).streak, 1)
        XCTAssertEqual(try entry(list, weekly).weekProgress, HabitWeekProgress(count: 1, target: 3))

        _ = list.toggleCheckOff(id: habit.id)
        _ = list.toggleCheckOff(id: weekly.id)
        XCTAssertEqual(try entry(list, habit).streak, 0)
        XCTAssertEqual(try entry(list, weekly).weekProgress, HabitWeekProgress(count: 0, target: 3))
    }

    func testAnEntryAgreesWithTodaysRowForTheSameHabit() throws {
        let list = try makeList(on: 7)
        let daily = try XCTUnwrap(list.addHabit(name: "Read"))
        let weekly = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        check(list, daily, on: [7, 8])
        check(list, weekly, on: [7, 8])

        for today in list.todayHabits {
            let listed = try XCTUnwrap(list.habitEntries.first { $0.id == today.id })
            XCTAssertEqual(listed.streak, today.streak, today.habit.name)
            XCTAssertEqual(listed.weekProgress, today.weekProgress, today.habit.name)
        }
    }
}
