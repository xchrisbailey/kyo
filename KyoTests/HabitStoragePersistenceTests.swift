import SwiftData
import XCTest

/// How phone and standalone habit stores keep their content in SwiftData (#70). September
/// 2026: the 27th is a Sunday, the 29th a Tuesday.
@MainActor
final class HabitStoragePersistenceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var now = Date()

    private func sep(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 10))!
    }

    private func completionDay(_ day: Int) -> TaskCompletionDay {
        TaskCompletionDay(date: sep(day), calendar: calendar)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HabitStoragePersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func makeList(
        _ container: ModelContainer, on day: Int, defaults: UserDefaults? = nil, sync: HabitListSync? = nil
    ) throws -> HabitListStore {
        now = sep(day)
        return HabitListStore(
            userDefaults: try defaults ?? makeDefaults(), modelContainer: container,
            now: { self.now }, calendar: calendar, sync: sync
        )
    }

    // MARK: Duplicates

    func testSeededDuplicateRecordsLoadOnce() throws {
        let container = try HabitStorage.makeContainer()
        let context = container.mainContext
        let created = completionDay(1)
        let habit = Habit(name: "Run", order: 0, createdOn: created)
        HabitStorage.seed([Habit(name: "Other", order: 1, createdOn: created)], in: container)

        // Two habit records share an id. The one with the log is the one kept.
        let kept = HabitRecord(habit: habit)
        let extra = HabitRecord(habit: habit)
        context.insert(kept)
        context.insert(extra)
        // The kept one repeats a check-off for one day and a schedule entry for one day.
        for day in [2, 2, 3] {
            let checkOff = HabitCheckOffRecord(day: completionDay(day))
            context.insert(checkOff)
            checkOff.habit = kept
        }
        for _ in 0..<2 {
            let entry = HabitScheduleRecord(entry: HabitScheduleEntry(schedule: .everyDay, from: created))
            context.insert(entry)
            entry.habit = kept
        }
        try context.save()

        let list = try makeList(container, on: 4)

        XCTAssertEqual(list.habits.map(\.name), ["Run", "Other"])
        let run = try XCTUnwrap(list.habits.first { $0.id == habit.id })
        XCTAssertEqual(run.checkOffs, [completionDay(2), completionDay(3)])
        XCTAssertEqual(run.scheduleHistory, [HabitScheduleEntry(schedule: .everyDay, from: created)])
        // The repeats were removed from storage, not just hidden.
        XCTAssertEqual(try HabitStorage.recordCount(HabitRecord.self, in: container), 2)
        XCTAssertEqual(try HabitStorage.recordCount(HabitCheckOffRecord.self, in: container), 2)
        XCTAssertEqual(try HabitStorage.recordCount(HabitScheduleRecord.self, in: container), 2)
        XCTAssertEqual(try makeList(container, on: 4).habits, list.habits)
    }

    // MARK: Delete

    func testDeletingAHabitRemovesItsCheckOffAndScheduleRecords() throws {
        let container = try HabitStorage.makeContainer()
        let list = try makeList(container, on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        _ = list.toggleCheckOff(id: habit.id)
        now = sep(2)
        _ = list.editHabit(id: habit.id, name: "Read", schedule: .weeklyTarget(3))
        _ = list.toggleCheckOff(id: habit.id)
        XCTAssertEqual(try HabitStorage.recordCount(HabitCheckOffRecord.self, in: container), 2)
        XCTAssertEqual(try HabitStorage.recordCount(HabitScheduleRecord.self, in: container), 2)

        _ = list.deleteHabit(id: habit.id)

        XCTAssertEqual(try HabitStorage.recordCount(HabitRecord.self, in: container), 0)
        XCTAssertEqual(try HabitStorage.recordCount(HabitCheckOffRecord.self, in: container), 0)
        XCTAssertEqual(try HabitStorage.recordCount(HabitScheduleRecord.self, in: container), 0)
        XCTAssertTrue(try makeList(container, on: 2).habits.isEmpty)
    }

    // MARK: Reopening

    func testCheckOffsOrderAndCreationDaysSurviveReopening() throws {
        let container = try HabitStorage.makeContainer()
        let list = try makeList(container, on: 1)
        let first = try XCTUnwrap(list.addHabit(name: "First"))
        now = sep(5)
        let second = try XCTUnwrap(list.addHabit(name: "Second"))
        for day in [5, 6, 7] {
            now = sep(day)
            list.refreshForCurrentDay()
            _ = list.toggleCheckOff(id: first.id)
        }
        list.moveHabits(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let reopened = try makeList(container, on: 7)

        XCTAssertEqual(reopened.habits, list.habits)
        XCTAssertEqual(reopened.habits.map(\.name), ["Second", "First"])
        XCTAssertEqual(reopened.habits.map(\.order), [0, 1])
        XCTAssertEqual(reopened.habits.first { $0.id == first.id }?.createdOn, completionDay(1))
        XCTAssertEqual(reopened.habits.first { $0.id == second.id }?.createdOn, completionDay(5))
        XCTAssertEqual(
            reopened.habits.first { $0.id == first.id }?.checkOffs.sorted { $0.day < $1.day },
            [completionDay(5), completionDay(6), completionDay(7)]
        )
    }

    func testAnUncheckedDayStaysUncheckedAfterReopening() throws {
        let container = try HabitStorage.makeContainer()
        let list = try makeList(container, on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        _ = list.toggleCheckOff(id: habit.id)
        _ = list.toggleCheckOff(id: habit.id)

        let reopened = try makeList(container, on: 1)

        XCTAssertEqual(reopened.habits.first?.checkOffs, [])
        XCTAssertEqual(try HabitStorage.recordCount(HabitCheckOffRecord.self, in: container), 0)
    }

    func testEveryScheduleKindRoundTripsThroughAReopen() throws {
        let container = try HabitStorage.makeContainer()
        let list = try makeList(container, on: 1)
        let schedules: [HabitSchedule] = [
            .everyDay,
            .weekdays([1]), .weekdays([7]), .weekdays([2, 4, 6]), .weekdays(Set(1...7)),
            .weeklyTarget(1), .weeklyTarget(6),
        ]
        for (index, schedule) in schedules.enumerated() {
            XCTAssertNotNil(list.addHabit(name: "Habit \(index)", schedule: schedule))
        }

        let reopened = try makeList(container, on: 1)

        XCTAssertEqual(reopened.habits.map(\.schedule), schedules)
    }

    func testScheduleHistoryAcrossKindsRoundTripsInOrder() throws {
        let container = try HabitStorage.makeContainer()
        let list = try makeList(container, on: 1)
        let habit = try XCTUnwrap(list.addHabit(name: "Read"))
        let edits: [(day: Int, schedule: HabitSchedule)] = [
            (5, .weekdays([1, 7])), (10, .weeklyTarget(3)), (15, .weekdays([2, 3, 4, 5, 6])), (20, .everyDay),
        ]
        for edit in edits {
            now = sep(edit.day)
            _ = list.editHabit(id: habit.id, name: "Read", schedule: edit.schedule)
        }
        // Editing again on the same day replaces that day's entry rather than adding one.
        _ = list.editHabit(id: habit.id, name: "Read", schedule: .weeklyTarget(2))

        let reopened = try makeList(container, on: 20)

        let history = try XCTUnwrap(reopened.habits.first).scheduleHistory
        XCTAssertEqual(history, list.habits.first?.scheduleHistory)
        XCTAssertEqual(history.map(\.schedule), [
            .everyDay, .weekdays([1, 7]), .weeklyTarget(3), .weekdays([2, 3, 4, 5, 6]), .weeklyTarget(2),
        ])
        XCTAssertEqual(history.map(\.from), [1, 5, 10, 15, 20].map(completionDay))
        XCTAssertEqual(try HabitStorage.recordCount(HabitScheduleRecord.self, in: container), 5)
    }

    // MARK: The old content key

    func testPhoneStoreLeavesTheHabitContentKeyUntouched() throws {
        let defaults = try makeDefaults()
        let container = try HabitStorage.makeContainer()
        let backup = Data("frozen backup".utf8)
        defaults.set(backup, forKey: HabitListStore.storageKey)

        let phone = try makeList(container, on: 1, defaults: defaults, sync: .publish(to: ControllableHabitTransport()))
        let habit = try XCTUnwrap(phone.addHabit(name: "Not in UserDefaults"))
        _ = phone.toggleCheckOff(id: habit.id)
        phone.moveHabits(fromOffsets: IndexSet(integer: 0), toOffset: 0)
        _ = phone.deleteHabit(id: habit.id)

        XCTAssertEqual(defaults.data(forKey: HabitListStore.storageKey), backup)
    }

    func testStandaloneStoreIgnoresHabitsLeftInTheContentKey() throws {
        let defaults = try makeDefaults()
        defaults.set(try JSONEncoder().encode([Habit(name: "Old backup", order: 0)]), forKey: HabitListStore.storageKey)

        let list = try makeList(try HabitStorage.makeContainer(), on: 1, defaults: defaults)

        XCTAssertTrue(list.habits.isEmpty)
    }

    func testWatchMirrorStillKeepsItsHabitsInUserDefaultsWithoutAContainer() throws {
        let defaults = try makeDefaults()
        let transport = ControllableHabitTransport()
        let watch = HabitListStore(
            userDefaults: defaults, now: { self.sep(7) }, calendar: calendar, sync: .mirror(from: transport)
        )
        let habit = Habit(name: "Walk", order: 0, createdOn: completionDay(1))

        transport.deliver(HabitListSnapshot(revision: 3, habits: [habit]))

        let stored = try JSONDecoder().decode([Habit].self, from: try XCTUnwrap(defaults.data(forKey: HabitListStore.storageKey)))
        XCTAssertEqual(stored, [habit])
        XCTAssertEqual(watch.habits, [habit])
    }
}
