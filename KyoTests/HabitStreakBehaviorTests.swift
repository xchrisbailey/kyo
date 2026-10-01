import XCTest

/// Streaks seen through the habit list. September 2026: Sundays fall on the 6th, 13th, 20th
/// and 27th; Mondays on the 7th, 14th, 21st and 28th.
@MainActor
final class HabitStreakBehaviorTests: XCTestCase {
    private let sunday = 1
    private let monday = 2
    private let wednesday = 4
    private let friday = 6

    private var now = Date()
    private var calendar = Calendar(identifier: .gregorian)

    private func makeList(firstWeekday: Int = 1, defaults: UserDefaults? = nil, startingOn start: Date? = nil) throws -> HabitListStore {
        calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        if let start { now = start }
        return HabitListStore(
            userDefaults: try defaults ?? makeDefaults(), storageKey: "habits", now: { self.now }, calendar: calendar
        )
    }

    private func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
    }

    private func sep(_ day: Int) -> Date { date(9, day) }

    /// Moves the clock to each day in turn and toggles the habit's check-off.
    private func check(_ list: HabitListStore, _ habit: Habit, on days: [Date]) {
        for day in days {
            now = day
            list.refreshForCurrentDay()
            _ = list.toggleCheckOff(id: habit.id)
        }
    }

    /// The first Today habit's streak on `day`.
    private func streak(_ list: HabitListStore, on day: Date) -> Int? {
        now = day
        list.refreshForCurrentDay()
        return list.todayHabits.first?.streak
    }

    private func streaksByName(_ list: HabitListStore) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: list.todayHabits.map { ($0.habit.name, $0.streak) })
    }

    // MARK: Day-based habits

    func testNonDueDaysNeitherAddToNorBreakAStreak() throws {
        let list = try makeList(startingOn: sep(7))
        let habit = try XCTUnwrap(list.addHabit(name: "Gym", schedule: .weekdays([monday, wednesday, friday])))
        check(list, habit, on: [sep(7), sep(9), sep(11)])

        // Saturday: not due, so not on Today.
        now = sep(12)
        list.refreshForCurrentDay()
        XCTAssertTrue(list.todayHabits.isEmpty)
        // Next Monday, still open: 3. Checked: 4.
        XCTAssertEqual(streak(list, on: sep(14)), 3)
        check(list, habit, on: [sep(14)])
        XCTAssertEqual(list.todayHabits.first?.streak, 4)
    }

    func testAMissedDueDayBreaksAWeekdayStreak() throws {
        let list = try makeList(startingOn: sep(7))
        let habit = try XCTUnwrap(list.addHabit(name: "Gym", schedule: .weekdays([monday, wednesday, friday])))
        check(list, habit, on: [sep(7), sep(11)]) // Wednesday the 9th missed

        XCTAssertEqual(streak(list, on: sep(14)), 1)
    }

    func testADueDayWithoutACheckOffBreaksTheStreak() throws {
        let list = try makeList(startingOn: sep(1))
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [sep(1), sep(2), sep(3), sep(5), sep(6)])

        // The 4th was missed; the run since is the 5th and 6th.
        XCTAssertEqual(streak(list, on: sep(6)), 2)
        // Today (the 7th) is open, so it still holds.
        XCTAssertEqual(streak(list, on: sep(7)), 2)
        // Once the 7th passes unchecked, the streak is broken.
        XCTAssertEqual(streak(list, on: sep(8)), 0)
    }

    func testAnUncheckedTodayNeverBreaksAndCheckingItAddsOne() throws {
        let list = try makeList(startingOn: sep(1))
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [sep(1), sep(2), sep(3)])

        XCTAssertEqual(streak(list, on: sep(4)), 3)
        check(list, habit, on: [sep(4)])
        XCTAssertEqual(list.todayHabits.first?.streak, 4)
        check(list, habit, on: [sep(4)]) // uncheck
        XCTAssertEqual(list.todayHabits.first?.streak, 3)
    }

    func testAHabitWithNoCheckOffsHasNoStreak() throws {
        let list = try makeList(startingOn: sep(1))
        _ = list.addHabit(name: "Read")
        XCTAssertEqual(streak(list, on: sep(1)), 0)
        XCTAssertEqual(streak(list, on: sep(20)), 0)
    }

    func testStreakStopsAtTheCreationDay() throws {
        let defaults = try makeDefaults()
        _ = try makeList(defaults: defaults, startingOn: sep(11))
        let habit = Habit(
            name: "Read", order: 0,
            checkOffs: [8, 9, 10, 11].map { TaskCompletionDay(date: sep($0), calendar: calendar) },
            createdOn: TaskCompletionDay(date: sep(10), calendar: calendar)
        )
        defaults.set(try JSONEncoder().encode([habit]), forKey: "habits")
        let list = try makeList(defaults: defaults, startingOn: sep(11))

        // The 8th and 9th predate the habit: neither hits nor misses; the streak just stops.
        XCTAssertEqual(streak(list, on: sep(11)), 2)
    }

    func testTheCreationDayItselfCanStartAStreak() throws {
        let list = try makeList(startingOn: sep(10))
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [sep(10)])
        XCTAssertEqual(list.todayHabits.first?.streak, 1)
        // The 11th is missed, so the streak is gone by the 12th.
        XCTAssertEqual(streak(list, on: sep(12)), 0)
    }

    func testALongRunAndALongGap() throws {
        let defaults = try makeDefaults()
        _ = try makeList(defaults: defaults)
        let start = date(1, 1, year: 2024)
        let days = (0..<1000).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        let log = days.map { TaskCompletionDay(date: $0, calendar: calendar) }
        let running = Habit(name: "Run", order: 0, checkOffs: log, createdOn: log[0])
        let lapsed = Habit(name: "Lapsed", order: 1, checkOffs: Array(log[0..<200]), createdOn: log[0])
        defaults.set(try JSONEncoder().encode([running, lapsed]), forKey: "habits")
        let list = try makeList(defaults: defaults, startingOn: days[999])

        XCTAssertEqual(streaksByName(list), ["Run": 1000, "Lapsed": 0])
    }

    func testStreakCountsBackAcrossAMonthAndYearBoundary() throws {
        let list = try makeList(startingOn: date(12, 30, year: 2025))
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [date(12, 30, year: 2025), date(12, 31, year: 2025), date(1, 1), date(1, 2)])
        XCTAssertEqual(list.todayHabits.first?.streak, 4)
    }

    // MARK: Weekly-target habits

    func testWeeklyStreakCountsConsecutiveWeeksWhoseTargetWasMet() throws {
        let list = try makeList(startingOn: sep(6))
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        // Weeks of the 6th, 13th and 20th each get two check-offs.
        check(list, habit, on: [sep(6), sep(7), sep(13), sep(14), sep(20), sep(21)])

        // The week of the 27th is in progress and unmet: it doesn't break the streak.
        XCTAssertEqual(streak(list, on: sep(28)), 3)
        check(list, habit, on: [sep(28)])
        XCTAssertEqual(list.todayHabits.first?.streak, 3)
        // Meeting this week's target adds one.
        check(list, habit, on: [sep(29)])
        XCTAssertEqual(list.todayHabits.first?.streak, 4)
    }

    func testAMissedWeekBreaksTheWeeklyStreak() throws {
        let list = try makeList(startingOn: sep(6))
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        // The week of the 13th has only one check-off.
        check(list, habit, on: [sep(6), sep(7), sep(14), sep(20), sep(21)])

        XCTAssertEqual(streak(list, on: sep(22)), 1)
        // The week of the 27th passes unmet.
        XCTAssertEqual(streak(list, on: date(10, 5)), 0)
    }

    func testCheckOffsBeyondTheTargetAddNothingMore() throws {
        let list = try makeList(startingOn: sep(6))
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        check(list, habit, on: [sep(6), sep(7), sep(8), sep(9), sep(10)])
        XCTAssertEqual(streak(list, on: sep(10)), 1)
        XCTAssertEqual(streak(list, on: sep(14)), 1)
    }

    func testFirstPartialWeekCountsWhenMet() throws {
        let list = try makeList(startingOn: sep(9)) // Wednesday
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        check(list, habit, on: [sep(9), sep(10)])

        XCTAssertEqual(list.todayHabits.first?.streak, 1)
        XCTAssertEqual(streak(list, on: sep(15)), 1)
        check(list, habit, on: [sep(15), sep(16)])
        XCTAssertEqual(list.todayHabits.first?.streak, 2)
    }

    func testFirstPartialWeekIsIgnoredWhenNotMet() throws {
        let list = try makeList(startingOn: sep(9))
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(3)))
        check(list, habit, on: [sep(9)]) // 1 of 3 in the week of the 6th

        // The week of the 13th is met; the unmet first week isn't a miss.
        check(list, habit, on: [sep(14), sep(15), sep(16)])
        XCTAssertEqual(streak(list, on: sep(20)), 1)
        check(list, habit, on: [sep(21), sep(22), sep(23)])
        XCTAssertEqual(list.todayHabits.first?.streak, 2)
        XCTAssertEqual(streak(list, on: sep(28)), 2)
        // A later unmet full week does break it.
        XCTAssertEqual(streak(list, on: date(10, 5)), 0)
    }

    func testStreakWeeksFollowTheCalendarsFirstWeekday() throws {
        // Saturday the 26th and Sunday the 27th share a week only when weeks start on Monday.
        for (firstWeekday, expected) in [(monday, 1), (sunday, 0)] {
            let list = try makeList(firstWeekday: firstWeekday, startingOn: sep(26))
            let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
            check(list, habit, on: [sep(26), sep(27)])
            XCTAssertEqual(streak(list, on: sep(28)), expected, "firstWeekday \(firstWeekday)")
        }
    }

    func testALongRunOfWeeksAndALongGap() throws {
        let defaults = try makeDefaults()
        _ = try makeList(defaults: defaults)
        let firstSunday = date(1, 7, year: 2024)
        let weeks = (0..<150).map { calendar.date(byAdding: .weekOfYear, value: $0, to: firstSunday)! }
        let log = weeks.flatMap { week in
            (0..<2).map { TaskCompletionDay(date: calendar.date(byAdding: .day, value: $0, to: week)!, calendar: calendar) }
        }
        let running = Habit(name: "Run", order: 0, schedule: .weeklyTarget(2), checkOffs: log, createdOn: log[0])
        let lapsed = Habit(name: "Lapsed", order: 1, schedule: .weeklyTarget(2), checkOffs: Array(log[0..<20]), createdOn: log[0])
        defaults.set(try JSONEncoder().encode([running, lapsed]), forKey: "habits")
        let list = try makeList(defaults: defaults, startingOn: weeks[149])

        XCTAssertEqual(streaksByName(list), ["Run": 150, "Lapsed": 0])
    }

    // MARK: Creation day

    func testAddedHabitsRecordTheirCreationDay() throws {
        let list = try makeList(startingOn: sep(9))
        let habit = try XCTUnwrap(list.addHabit(name: "Run"))
        XCTAssertEqual(habit.createdOn, TaskCompletionDay(date: sep(9), calendar: calendar))
    }

    func testOlderHabitsDecodeWithTheEarliestCheckOffAsCreationDay() throws {
        let defaults = try makeDefaults()
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Stretch","order":0,"schedule":{"everyDay":{}},
          "checkOffs":[{"era":1,"year":2026,"month":9,"day":10},{"era":1,"year":2026,"month":9,"day":8},
                       {"era":1,"year":2026,"month":9,"day":9}]}]
        """
        defaults.set(Data(json.utf8), forKey: "habits")
        let list = try makeList(defaults: defaults, startingOn: sep(10))

        XCTAssertEqual(list.habits.first?.createdOn, TaskCompletionDay(date: sep(8), calendar: calendar))
        XCTAssertEqual(list.todayHabits.first?.streak, 3)
    }

    func testOlderHabitsWithoutCheckOffsDecodeWithTodayAsCreationDayAndItPersists() throws {
        let defaults = try makeDefaults()
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Stretch","order":0,"schedule":{"everyDay":{}},"checkOffs":[]}]
        """
        defaults.set(Data(json.utf8), forKey: "habits")
        let list = try makeList(defaults: defaults, startingOn: sep(10))
        XCTAssertEqual(list.habits.first?.createdOn, TaskCompletionDay(date: sep(10), calendar: calendar))

        // A later launch keeps the day that was assigned.
        now = sep(20)
        let reopened = try makeList(defaults: defaults)
        XCTAssertEqual(reopened.habits.first?.createdOn, TaskCompletionDay(date: sep(10), calendar: calendar))
    }

    func testCreationDayPersistsAcrossReopening() throws {
        let defaults = try makeDefaults()
        let list = try makeList(defaults: defaults, startingOn: sep(9))
        _ = list.addHabit(name: "Run")
        now = sep(15)
        let reopened = try makeList(defaults: defaults)
        XCTAssertEqual(reopened.habits.first?.createdOn, TaskCompletionDay(date: sep(9), calendar: calendar))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HabitStreakBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
