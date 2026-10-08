import SwiftData
import XCTest

/// Editing and deleting habits, seen through the habit list. September 2026 starts on a
/// Tuesday: Sundays fall on the 6th, 13th and 20th; Mondays on the 7th, 14th and 21st. Weeks
/// start on Sunday.
@MainActor
final class HabitEditDeleteBehaviorTests: XCTestCase {
    private let monday = 2
    private let tuesday = 3
    private let wednesday = 4
    private let friday = 6
    private let saturday = 7

    private var now = Date()
    private let calendar = Calendar(identifier: .gregorian)

    private func sep(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 10))!
    }

    private func makeList(on start: Int, container: ModelContainer? = nil) throws -> HabitListStore {
        now = sep(start)
        return HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits",
            modelContainer: try container ?? HabitStorage.makeContainer(), now: { self.now }, calendar: calendar
        )
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

    private func today(_ list: HabitListStore, _ habit: Habit) -> TodayHabit? {
        list.todayHabits.first { $0.id == habit.id }
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HabitEditDeleteBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: Rename and validation

    func testRenamingKeepsLogStreakOrderAndCreationDay() throws {
        let list = try makeList(on: 1)
        let stretch = try XCTUnwrap(list.addHabit(name: "Stretch"))
        _ = list.addHabit(name: "Read")
        check(list, stretch, on: [1, 2, 3])
        let before = try XCTUnwrap(list.habits.first { $0.id == stretch.id })

        let renamed = try XCTUnwrap(list.editHabit(id: stretch.id, name: "  Yoga ", schedule: .everyDay))

        XCTAssertEqual(renamed.name, "Yoga")
        XCTAssertEqual(renamed.id, stretch.id)
        XCTAssertEqual(renamed.checkOffs, before.checkOffs)
        XCTAssertEqual(renamed.createdOn, before.createdOn)
        XCTAssertEqual(renamed.order, before.order)
        XCTAssertEqual(renamed.scheduleHistory, before.scheduleHistory, "a rename adds no schedule entry")
        XCTAssertEqual(list.habits.map(\.name), ["Yoga", "Read"])
        XCTAssertEqual(today(list, renamed)?.streak, 3)
        XCTAssertEqual(today(list, renamed)?.isCheckedOffToday, true)
    }

    func testEditsAreValidatedLikeAdds() throws {
        let list = try makeList(on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Run"))
        let before = list.habits

        XCTAssertNil(list.editHabit(id: habit.id, name: "   ", schedule: .everyDay))
        XCTAssertNil(list.editHabit(id: habit.id, name: "Run", schedule: .weekdays([])))
        XCTAssertNil(list.editHabit(id: habit.id, name: "Run", schedule: .weeklyTarget(7)))
        XCTAssertNil(list.editHabit(id: habit.id, name: "Run", schedule: .weeklyTarget(0)))
        XCTAssertNil(list.editHabit(id: UUID(), name: "Run", schedule: .everyDay))
        XCTAssertEqual(list.habits, before)
    }

    // MARK: Schedule history

    func testPastDaysKeepTheScheduleTheyHadSoAnEditNeverBreaksThem() throws {
        let list = try makeList(on: 7)
        let habit = try XCTUnwrap(list.addHabit(name: "Gym", schedule: .weekdays([monday, wednesday, friday])))
        check(list, habit, on: [7, 9, 11])

        // Monday the 14th: switch to Tuesdays only. Today is no longer due and has no check-off.
        go(list, to: 14)
        _ = list.editHabit(id: habit.id, name: "Gym", schedule: .weekdays([tuesday]))
        XCTAssertNil(today(list, habit))

        // The 7th, 9th and 11th still count as due days checked off under the old schedule.
        check(list, habit, on: [15])
        XCTAssertEqual(today(list, habit)?.streak, 4)
        let edited = try XCTUnwrap(list.habits.first)
        XCTAssertTrue(edited.isDue(on: sep(9), calendar: calendar))
        XCTAssertFalse(edited.isDue(on: sep(10), calendar: calendar))
        XCTAssertFalse(edited.isDue(on: sep(14), calendar: calendar))
        XCTAssertTrue(edited.isDue(on: sep(15), calendar: calendar))
    }

    func testPastMissesStayMissedSoAnEditNeverExcusesThem() throws {
        let list = try makeList(on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [1, 2, 4]) // Thursday the 3rd missed

        // Saturday the 5th: now only due on Saturdays. Under that schedule the 3rd would be excused.
        go(list, to: 5)
        _ = list.editHabit(id: habit.id, name: "Read", schedule: .weekdays([saturday]))
        check(list, habit, on: [5])

        XCTAssertEqual(today(list, habit)?.streak, 2, "the 5th and the 4th; the missed 3rd still breaks it")
    }

    func testReplacingTheScheduleTwiceOnOneDayKeepsOnlyTheLatestEntry() throws {
        let list = try makeList(on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        go(list, to: 8)

        _ = list.editHabit(id: habit.id, name: "Read", schedule: .weekdays([monday]))
        let twice = try XCTUnwrap(list.editHabit(id: habit.id, name: "Read", schedule: .weekdays([tuesday])))

        XCTAssertEqual(twice.scheduleHistory.count, 2)
        XCTAssertEqual(twice.schedule, .weekdays([tuesday]))
        XCTAssertTrue(twice.isDue(on: sep(5), calendar: calendar), "earlier days keep every day")
        XCTAssertTrue(twice.isDue(on: sep(8), calendar: calendar))
        XCTAssertFalse(twice.isDue(on: sep(9), calendar: calendar))
    }

    func testEditingOnTheCreationDayReplacesTheFirstEntry() throws {
        let list = try makeList(on: 8)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))

        let edited = try XCTUnwrap(list.editHabit(id: habit.id, name: "Read", schedule: .weeklyTarget(3)))

        XCTAssertEqual(edited.scheduleHistory.count, 1)
        XCTAssertEqual(edited.scheduleHistory.first?.from, edited.createdOn)
        XCTAssertEqual(edited.schedule, .weeklyTarget(3))
    }

    // MARK: Streaks across edits

    func testEditingWithinTheSameUnitCarriesTheStreakOver() throws {
        let list = try makeList(on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [1, 2, 3])

        go(list, to: 4)
        _ = list.editHabit(id: habit.id, name: "Read", schedule: .weekdays([monday, tuesday, wednesday, friday]))
        XCTAssertEqual(today(list, habit)?.streak, 3, "the 4th is a Friday not yet checked off")
        check(list, habit, on: [4])
        XCTAssertEqual(today(list, habit)?.streak, 4)

        // Back to every day: Saturday the 5th is due again and carries on.
        go(list, to: 5)
        _ = list.editHabit(id: habit.id, name: "Read", schedule: .everyDay)
        check(list, habit, on: [5])
        XCTAssertEqual(today(list, habit)?.streak, 5)
    }

    func testChangingOneWeeklyTargetToAnotherCarriesTheStreakOver() throws {
        let list = try makeList(on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        check(list, habit, on: [1, 2, 6, 7]) // two weeks, each meeting 2

        go(list, to: 14) // Monday of the third week
        _ = list.editHabit(id: habit.id, name: "Run", schedule: .weeklyTarget(3))
        XCTAssertEqual(today(list, habit)?.streak, 2, "past weeks keep the target they ended with")
        XCTAssertEqual(today(list, habit)?.weekProgress, HabitWeekProgress(count: 0, target: 3))
    }

    func testSwitchingFromDaysToAWeeklyTargetStartsANewStreakFromToday() throws {
        let list = try makeList(on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Run"))
        check(list, habit, on: [1, 2, 3, 6, 7])
        let log = try XCTUnwrap(list.habits.first).checkOffs

        go(list, to: 8)
        let switched = try XCTUnwrap(list.editHabit(id: habit.id, name: "Run", schedule: .weeklyTarget(2)))

        XCTAssertEqual(switched.checkOffs, log, "the log is untouched")
        // The week of the 6th has two check-offs, so it is met; the week before the switch is not reached.
        XCTAssertEqual(today(list, habit)?.streak, 1)
        XCTAssertEqual(today(list, habit)?.weekProgress, HabitWeekProgress(count: 2, target: 2))
    }

    func testSwitchingFromAWeeklyTargetToDaysStartsANewStreakFromToday() throws {
        let list = try makeList(on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        check(list, habit, on: [1, 2, 6, 7])

        go(list, to: 8)
        _ = list.editHabit(id: habit.id, name: "Run", schedule: .everyDay)
        XCTAssertEqual(today(list, habit)?.streak, 0, "the 6th and 7th were checked off but are before the switch")
        XCTAssertNil(today(list, habit)?.weekProgress)
        check(list, habit, on: [8])
        XCTAssertEqual(today(list, habit)?.streak, 1)
        check(list, habit, on: [9])
        XCTAssertEqual(today(list, habit)?.streak, 2)
    }

    func testAChangedWeeklyTargetAppliesToTheWholeCurrentWeek() throws {
        let list = try makeList(on: 6)
        let lowered = try XCTUnwrap(list.addHabit(name: "Lowered", schedule: .weeklyTarget(3)))
        let raised = try XCTUnwrap(list.addHabit(name: "Raised", schedule: .weeklyTarget(2)))
        check(list, lowered, on: [6, 7])
        check(list, raised, on: [6, 7])
        XCTAssertEqual(today(list, raised)?.streak, 1)
        XCTAssertEqual(today(list, lowered)?.streak, 0)

        go(list, to: 9)
        _ = list.editHabit(id: lowered.id, name: "Lowered", schedule: .weeklyTarget(2))
        _ = list.editHabit(id: raised.id, name: "Raised", schedule: .weeklyTarget(4))

        let loweredToday = try XCTUnwrap(today(list, lowered))
        XCTAssertEqual(loweredToday.weekProgress, HabitWeekProgress(count: 2, target: 2))
        XCTAssertTrue(loweredToday.isDone, "the 2 check-offs earlier this week meet the new target")
        XCTAssertEqual(loweredToday.streak, 1)
        let raisedToday = try XCTUnwrap(today(list, raised))
        XCTAssertEqual(raisedToday.weekProgress, HabitWeekProgress(count: 2, target: 4))
        XCTAssertFalse(raisedToday.isDone)
        XCTAssertEqual(raisedToday.streak, 0)
    }

    // MARK: Today becomes not due

    func testAnEditThatMakesTodayNotDueDropsTheHabitWhenItHasNoCheckOff() throws {
        let list = try makeList(on: 8) // Tuesday
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))

        _ = list.editHabit(id: habit.id, name: "Read", schedule: .weekdays([monday]))

        XCTAssertNil(today(list, habit))
        XCTAssertEqual(list.todayCount, 0)
        XCTAssertNil(list.toggleCheckOff(id: habit.id), "a habit that isn't due can't be checked off")
    }

    func testAnEditThatMakesTodayNotDueKeepsACheckedOffHabitUntilTheDayEnds() throws {
        let list = try makeList(on: 8)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        let other = try XCTUnwrap(list.addHabit(name: "Stretch"))
        check(list, habit, on: [8])

        _ = list.editHabit(id: habit.id, name: "Read", schedule: .weekdays([monday]))

        let entry = try XCTUnwrap(today(list, habit))
        XCTAssertTrue(entry.isDone)
        XCTAssertTrue(entry.isCheckedOffToday)
        XCTAssertEqual(entry.streak, 0, "the check-off doesn't count: the day isn't due")
        XCTAssertEqual(list.todayHabits.map(\.id), [other.id, habit.id], "it sits in the done group")
        XCTAssertEqual(list.doneCount, 1)

        // Still tappable: unchecking removes it from the list.
        XCTAssertNotNil(list.toggleCheckOff(id: habit.id))
        XCTAssertNil(today(list, habit))
        XCTAssertNil(list.toggleCheckOff(id: habit.id))
    }

    func testAHabitMadeNotDueStaysDueTodayOnlyWhileItHasACheckOff() throws {
        let list = try makeList(on: 8)
        let checked = try XCTUnwrap(list.addHabit(name: "Read"))
        let unchecked = try XCTUnwrap(list.addHabit(name: "Stretch"))
        check(list, checked, on: [8])

        _ = list.editHabit(id: checked.id, name: "Read", schedule: .weekdays([monday]))
        _ = list.editHabit(id: unchecked.id, name: "Stretch", schedule: .weekdays([monday]))

        let onToday = try XCTUnwrap(list.habitEntries.first { $0.id == checked.id })
        XCTAssertTrue(onToday.isDueToday, "it stays on Today's list, so the sheet doesn't mark it not due")
        XCTAssertEqual(onToday.streak, 0)
        let off = try XCTUnwrap(list.habitEntries.first { $0.id == unchecked.id })
        XCTAssertFalse(off.isDueToday)
        XCTAssertEqual(list.habitEntries.count, 2, "both stay listed")

        go(list, to: 9)
        XCTAssertFalse(try XCTUnwrap(list.habitEntries.first { $0.id == checked.id }).isDueToday)
    }

    func testAHabitMadeNotDueLeavesTheListOnceTheDayEnds() throws {
        let list = try makeList(on: 8)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [8])
        _ = list.editHabit(id: habit.id, name: "Read", schedule: .weekdays([monday]))
        XCTAssertNotNil(today(list, habit))

        go(list, to: 9)

        XCTAssertNil(today(list, habit))
        XCTAssertEqual(try XCTUnwrap(list.habits.first).checkOffs.count, 1, "the check-off stays in the log")
    }

    // MARK: Delete

    func testDeletingRemovesTheHabitAndItsLogForGood() throws {
        let container = try HabitStorage.makeContainer()
        let list = try makeList(on: 1, container: container)
        let doomed = try XCTUnwrap(list.addHabit(name: "Doomed"))
        let kept = try XCTUnwrap(list.addHabit(name: "Kept"))
        check(list, doomed, on: [1, 2])
        check(list, kept, on: [2])

        let removed = try XCTUnwrap(list.deleteHabit(id: doomed.id))

        XCTAssertEqual(removed.id, doomed.id)
        XCTAssertEqual(list.habits.map(\.name), ["Kept"])
        XCTAssertEqual(list.todayHabits.map(\.id), [kept.id])
        XCTAssertEqual(list.todayCount, 1)
        XCTAssertEqual(list.doneCount, 1)
        XCTAssertNil(list.deleteHabit(id: doomed.id))
        XCTAssertNil(list.toggleCheckOff(id: doomed.id))
        XCTAssertNil(list.editHabit(id: doomed.id, name: "Back", schedule: .everyDay))

        let reopened = try makeList(on: 2, container: container)
        XCTAssertEqual(reopened.habits.map(\.name), ["Kept"])
        XCTAssertEqual(reopened.habits.map(\.id), [kept.id])
        // The removed habit's check-offs and schedule entry went with it.
        XCTAssertEqual(try HabitStorage.recordCount(HabitRecord.self, in: container), 1)
        XCTAssertEqual(try HabitStorage.recordCount(HabitCheckOffRecord.self, in: container), 1)
        XCTAssertEqual(try HabitStorage.recordCount(HabitScheduleRecord.self, in: container), 1)
    }

    func testAnAddAfterADeleteStillGoesToTheEnd() throws {
        let list = try makeList(on: 1)
        _ = list.addHabit(name: "A")
        let b = try XCTUnwrap(list.addHabit(name: "B"))
        _ = list.addHabit(name: "C")
        _ = list.deleteHabit(id: b.id)

        _ = list.addHabit(name: "D")

        XCTAssertEqual(list.habits.map(\.name), ["A", "C", "D"])
    }

    // MARK: Persistence

    func testScheduleHistoryAndEditsPersistAcrossReopening() throws {
        let container = try HabitStorage.makeContainer()
        let list = try makeList(on: 1, container: container)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        check(list, habit, on: [1, 2, 3])
        go(list, to: 5)
        _ = list.editHabit(id: habit.id, name: "Reading", schedule: .weekdays([monday, saturday]))

        let reopened = try makeList(on: 5, container: container)

        let reloaded = try XCTUnwrap(reopened.habits.first)
        XCTAssertEqual(reloaded.name, "Reading")
        XCTAssertEqual(reloaded.scheduleHistory, list.habits.first?.scheduleHistory)
        XCTAssertEqual(reloaded.scheduleHistory.map(\.schedule), [.everyDay, .weekdays([monday, saturday])])
        XCTAssertTrue(reloaded.isDue(on: sep(4), calendar: calendar), "the 4th was judged by every day")
        XCTAssertFalse(reloaded.isDue(on: sep(9), calendar: calendar))
        XCTAssertEqual(reopened.todayHabits.first?.streak, today(list, habit)?.streak)
    }

    func testHabitsSavedWithASingleScheduleDecodeIntoAOneEntryHistoryFromCreation() throws {
        let container = try HabitStorage.makeContainer()
        let id = UUID()
        let encoded = try JSONEncoder().encode(HabitSchedule.weekdays([monday, wednesday, friday]))
        let schedule = String(decoding: encoded, as: UTF8.self)
        let json = """
        [{"id":"\(id.uuidString)","name":"Gym","order":0,
          "schedule":\(schedule),
          "checkOffs":[{"era":1,"year":2026,"month":9,"day":7}],
          "createdOn":{"era":1,"year":2026,"month":9,"day":1}}]
        """
        try HabitStorage.seed(json: json, in: container)

        let list = try makeList(on: 14, container: container)

        let habit = try XCTUnwrap(list.habits.first)
        XCTAssertEqual(habit.scheduleHistory.count, 1)
        XCTAssertEqual(habit.scheduleHistory.first?.schedule, .weekdays([monday, wednesday, friday]))
        XCTAssertEqual(habit.scheduleHistory.first?.from, habit.createdOn)
        XCTAssertEqual(habit.createdOn, TaskCompletionDay(date: sep(1), calendar: calendar))

        // Editing an old habit keeps its past under the old schedule.
        _ = list.editHabit(id: id, name: "Gym", schedule: .everyDay)
        let edited = try XCTUnwrap(list.habits.first)
        XCTAssertEqual(edited.scheduleHistory.count, 2)
        XCTAssertFalse(edited.isDue(on: sep(8), calendar: calendar))
        XCTAssertTrue(edited.isDue(on: sep(15), calendar: calendar))
    }

    func testOldHabitsWithoutACreationDayGetOneEntryStartingAtTheirBackfilledCreationDay() throws {
        let container = try HabitStorage.makeContainer()
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","name":"Stretch","order":0,"schedule":{"everyDay":{}},
          "checkOffs":[{"era":1,"year":2026,"month":9,"day":3}]}]
        """
        try HabitStorage.seed(json: json, in: container)

        let list = try makeList(on: 10, container: container)

        let habit = try XCTUnwrap(list.habits.first)
        let expectedStart = TaskCompletionDay(date: sep(3), calendar: calendar)
        XCTAssertEqual(habit.createdOn, expectedStart)
        XCTAssertEqual(habit.scheduleHistory, [HabitScheduleEntry(schedule: .everyDay, from: expectedStart)])
    }
}
