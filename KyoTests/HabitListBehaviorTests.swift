import SwiftData
import XCTest

@MainActor
final class HabitListBehaviorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let sunday = 1
    private let monday = 2
    private let tuesday = 3
    private let wednesday = 4

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    func testAddingHabitsTrimsNameAndPreservesCreationOrder() throws {
        let list: any HabitListBehavior = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer())

        let first = try XCTUnwrap(list.addHabit(name: "  Read  "))
        let second = try XCTUnwrap(list.addHabit(name: "Walk"))

        XCTAssertEqual(list.habits.map(\.name), ["Read", "Walk"])
        XCTAssertEqual(list.habits.map(\.order), [0, 1])
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Read", "Walk"])
        XCTAssertEqual(list.todayCount, 2)
        XCTAssertEqual(list.doneCount, 0)
    }

    func testBlankNameDoesNotCreateAHabit() throws {
        let list: any HabitListBehavior = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer())

        XCTAssertNil(list.addHabit(name: " \n\t "))
        XCTAssertTrue(list.habits.isEmpty)
        XCTAssertEqual(list.todayCount, 0)
    }

    func testHasHabitsIsTrueOnlyWhileAnyHabitExistsEvenWhenNoneIsDueToday() throws {
        let list: any HabitListBehavior = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
        )
        XCTAssertFalse(list.hasHabits)

        let weekday = calendar.component(.weekday, from: day(29))
        let otherDay = weekday % 7 + 1
        let elsewhere = try XCTUnwrap(list.addHabit(name: "Elsewhere", schedule: .weekdays([otherDay])))

        XCTAssertTrue(list.todayHabits.isEmpty)
        XCTAssertTrue(list.hasHabits)

        list.deleteHabit(id: elsewhere.id)
        XCTAssertFalse(list.hasHabits)
    }

    func testCheckingOffMovesHabitToDoneGroupAndUncheckingRestoresIt() throws {
        let list: any HabitListBehavior = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
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
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
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
        let list = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer())
        XCTAssertNil(list.toggleCheckOff(id: UUID()))
    }

    func testHabitsAndCheckOffsPersistAcrossReopening() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        let now = day(29)
        let list = HabitListStore(userDefaults: defaults, storageKey: "habits", modelContainer: container, now: { now }, calendar: calendar)
        let first = try XCTUnwrap(list.addHabit(name: "First"))
        _ = list.addHabit(name: "Second")
        _ = list.toggleCheckOff(id: first.id)

        let reopened = HabitListStore(userDefaults: defaults, storageKey: "habits", modelContainer: container, now: { now }, calendar: calendar)

        XCTAssertEqual(reopened.habits, list.habits)
        XCTAssertEqual(reopened.todayHabits, list.todayHabits)
        XCTAssertEqual(reopened.doneCount, 1)
        let third = try XCTUnwrap(reopened.addHabit(name: "Third"))
        XCTAssertEqual(third.order, 2)
    }

    func testCheckOffsAreKeyedToTheCurrentDay() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        var now = day(28, hour: 21)
        let list = HabitListStore(userDefaults: defaults, storageKey: "habits", modelContainer: container, now: { now }, calendar: calendar)
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

        let reopened = HabitListStore(userDefaults: defaults, storageKey: "habits", modelContainer: container, now: { now }, calendar: calendar)
        XCTAssertEqual(reopened.doneCount, 0)
    }

    func testHabitsAndTasksAreStoredApartInTheSameContainer() throws {
        let container = try makeContainer()
        let list = HabitListStore(userDefaults: try makeDefaults(), modelContainer: container)
        _ = list.addHabit(name: "Walk")

        XCTAssertNotEqual(HabitListStore.storageKey, TaskListStore.storageKey)
        XCTAssertTrue(TaskListStore(userDefaults: try makeDefaults(), modelContainer: container).tasks.isEmpty)
        XCTAssertEqual(HabitListStore(userDefaults: try makeDefaults(), modelContainer: container).habits.map(\.name), ["Walk"])
    }

    // MARK: Schedules (September 2026: the 27th is a Sunday, the 29th a Tuesday)

    func testSpecificWeekdayHabitsAppearOnlyOnTheirDays() throws {
        var now = day(29) // Tuesday
        let list = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { now }, calendar: calendar)
        _ = list.addHabit(name: "Every", schedule: .everyDay)
        _ = list.addHabit(name: "Tue/Thu", schedule: .weekdays([tuesday, tuesday + 2]))
        _ = list.addHabit(name: "Mon", schedule: .weekdays([monday]))
        _ = list.addHabit(name: "Weekly", schedule: .weeklyTarget(2))

        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Every", "Tue/Thu", "Weekly"])
        XCTAssertEqual(list.todayCount, 3)

        now = day(28) // Monday
        list.refreshForCurrentDay()
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Every", "Mon", "Weekly"])

        now = day(30) // Wednesday
        list.refreshForCurrentDay()
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Every", "Weekly"])
    }

    func testNothingDueTodayWhenHabitsExistButNoneAreDue() throws {
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
        )
        XCTAssertTrue(list.habits.isEmpty)
        _ = list.addHabit(name: "Monday only", schedule: .weekdays([monday]))

        XCTAssertFalse(list.habits.isEmpty)
        XCTAssertTrue(list.todayHabits.isEmpty)
        XCTAssertEqual(list.todayCount, 0)
        XCTAssertEqual(list.doneCount, 0)
    }

    func testCollapsedSummaryCountsDoneHabitsOnTodaysList() throws {
        let list: any HabitListBehavior = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
        )
        XCTAssertEqual(list.collapsedSummary, "No habits")

        let read = try XCTUnwrap(list.addHabit(name: "Read"))
        _ = list.addHabit(name: "Walk")
        _ = list.addHabit(name: "Stretch")
        _ = list.addHabit(name: "Monday only", schedule: .weekdays([monday])) // 2026-09-29 is a Tuesday
        XCTAssertEqual(list.collapsedSummary, "0 of 3 done")

        _ = list.toggleCheckOff(id: read.id)
        XCTAssertEqual(list.collapsedSummary, "1 of 3 done")

        _ = list.toggleCheckOff(id: read.id)
        XCTAssertEqual(list.collapsedSummary, "0 of 3 done")
    }

    func testCollapsedSummaryDistinguishesNoHabitsFromNothingDueToday() throws {
        let list: any HabitListBehavior = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
        )
        XCTAssertEqual(list.collapsedSummary, "No habits")

        let mondayOnly = try XCTUnwrap(list.addHabit(name: "Monday only", schedule: .weekdays([monday])))
        XCTAssertEqual(list.collapsedSummary, "Nothing due today")

        _ = list.deleteHabit(id: mondayOnly.id)
        XCTAssertEqual(list.collapsedSummary, "No habits")
    }

    func testInvalidSchedulesAreRejected() throws {
        let list: any HabitListBehavior = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer())

        XCTAssertNil(list.addHabit(name: "A", schedule: .weekdays([])))
        XCTAssertNil(list.addHabit(name: "B", schedule: .weeklyTarget(0)))
        XCTAssertNil(list.addHabit(name: "C", schedule: .weeklyTarget(7)))
        XCTAssertNotNil(list.addHabit(name: "D", schedule: .weeklyTarget(1)))
        XCTAssertNotNil(list.addHabit(name: "E", schedule: .weeklyTarget(6)))
        XCTAssertEqual(list.habits.map(\.name), ["D", "E"])
    }

    func testHabitThatIsNotDueCannotBeCheckedOff() throws {
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
        )
        let habit = try XCTUnwrap(list.addHabit(name: "Monday only", schedule: .weekdays([monday])))

        XCTAssertNil(list.toggleCheckOff(id: habit.id))
        XCTAssertTrue(try XCTUnwrap(list.habits.first).checkOffs.isEmpty)
    }

    func testSpecificWeekdayHabitIsDoneOnceCheckedOffOnItsDay() throws {
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
        )
        let habit = try XCTUnwrap(list.addHabit(name: "Tuesdays", schedule: .weekdays([tuesday])))
        _ = list.addHabit(name: "Other")

        _ = list.toggleCheckOff(id: habit.id)

        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Other", "Tuesdays"])
        XCTAssertEqual(list.doneCount, 1)
        XCTAssertEqual(list.todayCount, 2)
        XCTAssertNil(list.todayHabits.last?.weekProgress)
    }

    // MARK: Week progress

    func testWeekProgressCountsThisWeeksCheckOffsForBothFirstWeekdays() throws {
        for firstWeekday in [sunday, monday] {
            var now = day(27) // Sunday
            let cal = calendar(firstWeekday: firstWeekday)
            let list = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { now }, calendar: cal)
            let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(3)))
            _ = list.toggleCheckOff(id: habit.id) // Sunday

            now = day(29) // Tuesday
            list.refreshForCurrentDay()
            _ = list.toggleCheckOff(id: habit.id)

            // Sunday-first: Sun 27 and Tue 29 share a week. Monday-first: Sunday ended the prior week.
            let expected = firstWeekday == sunday ? 2 : 1
            XCTAssertEqual(
                list.todayHabits.first?.weekProgress, HabitWeekProgress(count: expected, target: 3),
                "firstWeekday \(firstWeekday)"
            )
        }
    }

    func testSundayFirstWeekBoundaryResetsProgress() throws {
        // Saturday Oct 3 closes the Sunday-first week; Sunday Oct 4 opens the next.
        var now = day(29)
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { now }, calendar: calendar(firstWeekday: sunday)
        )
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(1)))
        _ = list.toggleCheckOff(id: habit.id)
        XCTAssertEqual(list.todayHabits.first?.weekProgress?.count, 1)

        now = date(month: 10, day: 3)
        list.refreshForCurrentDay()
        XCTAssertEqual(list.todayHabits.first?.weekProgress?.count, 1)
        XCTAssertEqual(list.todayHabits.first?.isDone, true)

        now = date(month: 10, day: 4)
        list.refreshForCurrentDay()
        XCTAssertEqual(list.todayHabits.first?.weekProgress?.count, 0)
        XCTAssertEqual(list.todayHabits.first?.isDone, false)
    }

    func testMondayFirstWeekRunsThroughSunday() throws {
        var now = day(28) // Monday
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { now }, calendar: calendar(firstWeekday: monday)
        )
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        _ = list.toggleCheckOff(id: habit.id)

        now = date(month: 10, day: 4) // Sunday: still the same week
        list.refreshForCurrentDay()
        XCTAssertEqual(list.todayHabits.first?.weekProgress?.count, 1)

        now = date(month: 10, day: 5) // Monday: new week
        list.refreshForCurrentDay()
        XCTAssertEqual(list.todayHabits.first?.weekProgress?.count, 0)
    }

    func testWeekProgressCanExceedTheTargetAndCountsOneCheckOffPerDay() throws {
        var now = day(27)
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { now }, calendar: calendar(firstWeekday: sunday)
        )
        let habit = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(3)))
        for d in 27...30 {
            now = day(d)
            list.refreshForCurrentDay()
            _ = list.toggleCheckOff(id: habit.id)
        }

        XCTAssertEqual(list.todayHabits.first?.weekProgress, HabitWeekProgress(count: 4, target: 3))

        // Toggling again on the same day removes it rather than double-counting.
        _ = list.toggleCheckOff(id: habit.id)
        XCTAssertEqual(list.todayHabits.first?.weekProgress?.count, 3)
        _ = list.toggleCheckOff(id: habit.id)
        XCTAssertEqual(list.todayHabits.first?.weekProgress?.count, 4)
    }

    func testDuplicateLogEntriesForADayCountOnce() throws {
        let container = try makeContainer()
        let today = TaskCompletionDay(date: day(29), calendar: calendar)
        let habit = Habit(name: "Run", order: 0, schedule: .weeklyTarget(3), checkOffs: [today, today])
        HabitStorage.seed([habit], in: container)

        let list = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: container, now: { self.day(29) }, calendar: calendar)

        XCTAssertEqual(list.todayHabits.first?.weekProgress?.count, 1)
    }

    func testHabitCreatedMidWeekKeepsTheFullTarget() throws {
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(1, month: 10) }, calendar: calendar(firstWeekday: sunday)
        )
        _ = list.addHabit(name: "Run", schedule: .weeklyTarget(5)) // Thursday

        XCTAssertEqual(list.todayHabits.first?.weekProgress, HabitWeekProgress(count: 0, target: 5))
        XCTAssertEqual(list.todayHabits.first?.isDone, false)
    }

    // MARK: Met target and the done group

    func testMetTargetHabitIsDoneWithAnEmptyTappableCircleThenTappingAddsToday() throws {
        var now = day(27)
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { now }, calendar: calendar(firstWeekday: sunday)
        )
        let weekly = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(3)))
        _ = list.addHabit(name: "Read")
        for d in 27...29 {
            now = day(d)
            list.refreshForCurrentDay()
            _ = list.toggleCheckOff(id: weekly.id)
        }

        // Wednesday: target met on Sun-Tue, not checked off today.
        now = day(30)
        list.refreshForCurrentDay()
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Read", "Run"])
        let met = try XCTUnwrap(list.todayHabits.last)
        XCTAssertTrue(met.isDone)
        XCTAssertFalse(met.isCheckedOffToday)
        XCTAssertEqual(met.weekProgress, HabitWeekProgress(count: 3, target: 3))
        XCTAssertEqual(list.doneCount, 1)
        XCTAssertEqual(list.todayCount, 2)

        // Tapping the still-tappable circle adds Today's check-off: 4/3.
        XCTAssertNotNil(list.toggleCheckOff(id: weekly.id))
        let after = try XCTUnwrap(list.todayHabits.last)
        XCTAssertTrue(after.isDone)
        XCTAssertTrue(after.isCheckedOffToday)
        XCTAssertEqual(after.weekProgress, HabitWeekProgress(count: 4, target: 3))

        // Unchecking removes only Today's check-off; the target is still met.
        _ = list.toggleCheckOff(id: weekly.id)
        let undone = try XCTUnwrap(list.todayHabits.last)
        XCTAssertTrue(undone.isDone)
        XCTAssertFalse(undone.isCheckedOffToday)
        XCTAssertEqual(undone.weekProgress?.count, 3)
    }

    func testUnmetWeeklyTargetStaysInTheToDoGroupUntilMet() throws {
        var now = day(28)
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { now }, calendar: calendar(firstWeekday: monday)
        )
        let weekly = try XCTUnwrap(list.addHabit(name: "Run", schedule: .weeklyTarget(2)))
        _ = list.toggleCheckOff(id: weekly.id)

        // Checked off today, so it's done even though 1/2 isn't the target.
        XCTAssertEqual(list.todayHabits.first?.isDone, true)

        now = day(29)
        list.refreshForCurrentDay()
        XCTAssertEqual(list.todayHabits.first?.isDone, false)
        XCTAssertEqual(list.todayHabits.first?.weekProgress, HabitWeekProgress(count: 1, target: 2))
        XCTAssertEqual(list.doneCount, 0)
        XCTAssertEqual(list.todayCount, 1)
    }

    func testSummaryCountsOnlyHabitsOnTodaysList() throws {
        let list = HabitListStore(
            userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: try makeContainer(), now: { self.day(29) }, calendar: calendar
        )
        let a = try XCTUnwrap(list.addHabit(name: "A"))
        _ = list.addHabit(name: "B", schedule: .weekdays([tuesday]))
        _ = list.addHabit(name: "C", schedule: .weekdays([wednesday]))
        _ = list.addHabit(name: "D", schedule: .weeklyTarget(1))
        _ = list.toggleCheckOff(id: a.id)

        XCTAssertEqual(list.todayCount, 3)
        XCTAssertEqual(list.doneCount, 1)
    }

    func testSchedulesPersistAcrossReopening() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        let list = HabitListStore(userDefaults: defaults, storageKey: "habits", modelContainer: container, now: { self.day(29) }, calendar: calendar)
        _ = list.addHabit(name: "A", schedule: .weekdays([monday, wednesday]))
        _ = list.addHabit(name: "B", schedule: .weeklyTarget(4))

        let reopened = HabitListStore(userDefaults: defaults, storageKey: "habits", modelContainer: container, now: { self.day(29) }, calendar: calendar)

        XCTAssertEqual(reopened.habits.map(\.schedule), [.weekdays([monday, wednesday]), .weeklyTarget(4)])
    }

    func testPersistedEveryDayHabitsFromEarlierVersionsStillDecode() throws {
        let container = try makeContainer()
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","name":"Stretch","order":0,"schedule":{"everyDay":{}},
          "checkOffs":[{"era":1,"year":2026,"month":9,"day":29}]}]
        """
        try HabitStorage.seed(json: json, in: container)

        let list = HabitListStore(userDefaults: try makeDefaults(), storageKey: "habits", modelContainer: container, now: { self.day(29) }, calendar: calendar)

        XCTAssertEqual(list.habits.map(\.schedule), [.everyDay])
        XCTAssertEqual(list.todayHabits.map(\.habit.name), ["Stretch"])
        XCTAssertEqual(list.todayHabits.map(\.isCheckedOffToday), [true])
    }

    func testWeekdaysAreListedInTheCalendarsWeekOrder() {
        XCTAssertEqual(HabitSchedule.weekdaysInWeekOrder(calendar: calendar(firstWeekday: sunday)), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(HabitSchedule.weekdaysInWeekOrder(calendar: calendar(firstWeekday: monday)), [2, 3, 4, 5, 6, 7, 1])
    }

    private func date(month: Int, day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func day(_ day: Int, month: Int = 9, hour: Int = 10) -> Date {
        date(month: month, day: day, hour: hour)
    }

    private func makeContainer() throws -> ModelContainer {
        try HabitStorage.makeContainer()
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HabitListBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
