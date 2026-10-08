import SwiftData
import XCTest

/// The one-time move of tasks and habits from UserDefaults into SwiftData (#71). September
/// 2026: the 27th is a Sunday, the 29th a Tuesday.
@MainActor
final class UserDefaultsImportTests: XCTestCase {
    private struct SaveFailure: Error {}

    private let calendar = Calendar(identifier: .gregorian)

    private var now: Date { sep(29) }

    private func sep(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 10))!
    }

    private func day(_ day: Int) -> TaskCompletionDay {
        TaskCompletionDay(date: sep(day), calendar: calendar)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "UserDefaultsImportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func makeContainer() throws -> ModelContainer {
        try KyoModelContainer.make(inMemory: true)
    }

    private func makeImport(
        _ defaults: UserDefaults,
        _ container: ModelContainer,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) -> UserDefaultsImport {
        UserDefaultsImport(userDefaults: defaults, modelContainer: container, save: save)
    }

    private func makeTaskList(_ defaults: UserDefaults, _ container: ModelContainer, sync: TaskListSync? = nil) -> TaskListStore {
        TaskListStore(userDefaults: defaults, modelContainer: container, now: { self.now }, calendar: calendar, sync: sync)
    }

    private func makeHabitList(_ defaults: UserDefaults, _ container: ModelContainer, sync: HabitListSync? = nil) -> HabitListStore {
        HabitListStore(userDefaults: defaults, modelContainer: container, now: { self.now }, calendar: calendar, sync: sync)
    }

    private func count<Model: PersistentModel>(_ type: Model.Type, in container: ModelContainer) throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<Model>())
    }

    private func isDone(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: UserDefaultsImport.doneKey) != nil
    }

    // MARK: Legacy data

    private lazy var legacyTasks: [DailyTask] = [
        DailyTask(text: "Open", creationOrder: 0),
        DailyTask(text: "Finished", creationOrder: 1, isComplete: true, completedOn: day(29)),
        DailyTask(text: "Also open", creationOrder: 2),
    ]

    /// What the list shows for `legacyTasks`: open tasks in creation order, then completed ones.
    private var expectedTasks: [DailyTask] { [legacyTasks[0], legacyTasks[2], legacyTasks[1]] }

    /// One habit of each schedule kind, saved out of habit order, with check-offs and a
    /// habit that changed schedule twice.
    private lazy var legacyHabits: [Habit] = {
        let created = day(1)
        return [
            Habit(
                name: "Read", order: 2, checkOffs: [day(27), day(28)], createdOn: created,
                scheduleHistory: [HabitScheduleEntry(schedule: .weeklyTarget(3), from: created)]
            ),
            Habit(
                name: "Run", order: 0, checkOffs: [day(27), day(28), day(29)], createdOn: created,
                scheduleHistory: [HabitScheduleEntry(schedule: .everyDay, from: created)]
            ),
            Habit(
                name: "Gym", order: 1, checkOffs: [day(28)], createdOn: created,
                scheduleHistory: [
                    HabitScheduleEntry(schedule: .everyDay, from: created),
                    HabitScheduleEntry(schedule: .weekdays([2, 4, 6]), from: day(20)),
                    HabitScheduleEntry(schedule: .weekdays([3, 5]), from: day(27)),
                ]
            ),
        ]
    }()

    private func seedLegacy(_ defaults: UserDefaults, tasks: [DailyTask]? = nil, habits: [Habit]? = nil) throws {
        defaults.set(try JSONEncoder().encode(tasks ?? legacyTasks), forKey: TaskListStore.storageKey)
        defaults.set(try JSONEncoder().encode(habits ?? legacyHabits), forKey: HabitListStore.storageKey)
    }

    /// A copy of the legacy keys in a fresh suite, so a `.mirror` oracle can load and re-save
    /// them without touching the defaults under test.
    private func seededCopy(of defaults: UserDefaults) throws -> UserDefaults {
        let copy = try makeDefaults()
        for key in [TaskListStore.storageKey, HabitListStore.storageKey] {
            copy.set(defaults.data(forKey: key), forKey: key)
        }
        return copy
    }

    /// A store reading the same JSON from its content key, the way a phone did before
    /// SwiftData, for comparison with an imported store.
    private func legacyTaskList(from defaults: UserDefaults) -> TaskListStore {
        TaskListStore(
            userDefaults: defaults, now: { self.now }, calendar: calendar,
            sync: .mirror(from: ControllableTaskTransport())
        )
    }

    private func legacyHabitList(from defaults: UserDefaults) -> HabitListStore {
        HabitListStore(
            userDefaults: defaults, now: { self.now }, calendar: calendar,
            sync: .mirror(from: ControllableHabitTransport())
        )
    }

    // MARK: Content

    func testImportedTasksMatchWhatTheUserDefaultsStoreShowed() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)
        let legacy = legacyTaskList(from: try seededCopy(of: defaults))

        XCTAssertEqual(makeImport(defaults, container).run(), .imported)

        let imported = makeTaskList(defaults, container)
        XCTAssertEqual(imported.tasks.map(\.text), ["Open", "Also open", "Finished"])
        XCTAssertTrue(imported.tasks[2].isComplete)
        XCTAssertEqual(imported.tasks[2].completedOn, day(29))
        XCTAssertEqual(imported.tasks, expectedTasks)
        XCTAssertEqual(imported.tasks, legacy.tasks)
    }

    func testTasksCompletedOnAnEarlierDayAreClearedAsBefore() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        let tasks = [
            DailyTask(text: "Done yesterday", creationOrder: 0, isComplete: true, completedOn: day(28)),
            DailyTask(text: "Open", creationOrder: 1),
        ]
        try seedLegacy(defaults, tasks: tasks)
        let legacy = legacyTaskList(from: try seededCopy(of: defaults))

        makeImport(defaults, container).run()

        XCTAssertEqual(try count(TaskRecord.self, in: container), 2)
        XCTAssertEqual(makeTaskList(defaults, container).tasks, legacy.tasks)
        XCTAssertEqual(legacy.tasks.map(\.text), ["Open"])
    }

    func testImportedHabitsMatchWhatTheUserDefaultsStoreShowed() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)
        let legacy = legacyHabitList(from: try seededCopy(of: defaults))

        makeImport(defaults, container).run()

        let imported = makeHabitList(defaults, container)
        XCTAssertEqual(imported.habits.map(\.name), ["Run", "Gym", "Read"])
        XCTAssertEqual(imported.habits, legacy.habits)
        XCTAssertEqual(imported.todayHabits, legacy.todayHabits)
        XCTAssertEqual(imported.todayCount, legacy.todayCount)
        XCTAssertEqual(imported.doneCount, legacy.doneCount)

        // Spelled out, so the comparison above can't pass by both sides being wrong.
        let today = Dictionary(uniqueKeysWithValues: imported.todayHabits.map { ($0.habit.name, $0) })
        XCTAssertEqual(today["Run"]?.streak, 3)
        XCTAssertEqual(today["Run"]?.isCheckedOffToday, true)
        XCTAssertEqual(today["Read"]?.weekProgress, HabitWeekProgress(count: 2, target: 3))
        XCTAssertEqual(today["Read"]?.isDone, false)
        // Gym's latest schedule (Tuesday, Thursday) puts it on Today, unchecked.
        XCTAssertEqual(today["Gym"]?.isCheckedOffToday, false)
        let gym = try XCTUnwrap(imported.habits.first { $0.name == "Gym" })
        XCTAssertEqual(gym.scheduleHistory.count, 3)
        XCTAssertEqual(gym.schedule, .weekdays([3, 5]))
        XCTAssertEqual(gym.checkOffs, [day(28)])
        XCTAssertEqual(try count(HabitCheckOffRecord.self, in: container), 6)
        XCTAssertEqual(try count(HabitScheduleRecord.self, in: container), 5)
    }

    func testLegacyHabitsWithoutScheduleHistoryOrCreationDayBehaveAsBefore() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        let oldest = UUID()
        let newest = UUID()
        // Saved before schedule history (a lone `schedule`) and before creation days.
        let json = """
        [
          {"id":"\(oldest.uuidString)","name":"Stretch","order":0,
           "schedule":{"everyDay":{}},
           "checkOffs":[{"era":1,"year":2026,"month":9,"day":27},{"era":1,"year":2026,"month":9,"day":28},{"era":1,"year":2026,"month":9,"day":29}]},
          {"id":"\(newest.uuidString)","name":"Journal","order":1}
        ]
        """
        defaults.set(Data(json.utf8), forKey: HabitListStore.storageKey)
        let legacy = legacyHabitList(from: try seededCopy(of: defaults))
        XCTAssertEqual(legacy.habits.count, 2)

        makeImport(defaults, container).run()

        let imported = makeHabitList(defaults, container)
        XCTAssertEqual(imported.habits, legacy.habits)
        XCTAssertEqual(imported.todayHabits, legacy.todayHabits)
        XCTAssertEqual(imported.todayHabits.map(\.habit.name), ["Journal", "Stretch"])
        let stretch = try XCTUnwrap(imported.habits.first { $0.id == oldest })
        XCTAssertEqual(stretch.createdOn, day(27))   // backfilled from the earliest check-off
        XCTAssertEqual(stretch.streak(on: now, calendar: calendar), 3)
        let journal = try XCTUnwrap(imported.habits.first { $0.id == newest })
        XCTAssertEqual(journal.createdOn, day(29))   // backfilled with the day of this launch
        // The backfill survives reopening.
        XCTAssertEqual(makeHabitList(defaults, container).habits, imported.habits)
    }

    func testImportDoesNotBackfillCreationDays() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        let json = #"[{"id":"\#(UUID().uuidString)","name":"Journal","order":0}]"#
        defaults.set(Data(json.utf8), forKey: HabitListStore.storageKey)

        makeImport(defaults, container).run()

        let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<HabitRecord>()).first)
        XCTAssertNil(record.createdOn)
    }

    // MARK: Watch link and backup

    private let linkSuffixes = [".revision", ".tombstones", ".processedCommands", ".outbox", ""]

    private func seedWatchLink(_ defaults: UserDefaults, base: String, revision: Int64) throws {
        defaults.set(NSNumber(value: revision), forKey: base + ".revision")
        defaults.set(try JSONEncoder().encode([UUID(), UUID()]), forKey: base + ".tombstones")
        defaults.set(try JSONEncoder().encode([UUID()]), forKey: base + ".processedCommands")
        defaults.set(Data("pending commands".utf8), forKey: base + ".outbox")
    }

    /// Every Watch-link key and the content key under `base`, as stored.
    private func values(_ defaults: UserDefaults, base: String) -> NSDictionary {
        var found: [String: Any] = [:]
        for suffix in linkSuffixes {
            found[suffix] = defaults.object(forKey: base + suffix)
        }
        return found as NSDictionary
    }

    func testWatchLinkRecordsAndContentKeysAreLeftUntouched() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)
        try seedWatchLink(defaults, base: TaskListStore.storageKey, revision: 111)
        try seedWatchLink(defaults, base: HabitListStore.storageKey, revision: 222)
        let tasksBefore = values(defaults, base: TaskListStore.storageKey)
        let habitsBefore = values(defaults, base: HabitListStore.storageKey)
        let taskContentBefore = try XCTUnwrap(defaults.data(forKey: TaskListStore.storageKey))
        let habitContentBefore = try XCTUnwrap(defaults.data(forKey: HabitListStore.storageKey))

        XCTAssertEqual(makeImport(defaults, container).run(), .imported)

        XCTAssertEqual(values(defaults, base: TaskListStore.storageKey), tasksBefore)
        XCTAssertEqual(values(defaults, base: HabitListStore.storageKey), habitsBefore)
        XCTAssertEqual(defaults.data(forKey: TaskListStore.storageKey), taskContentBefore)
        XCTAssertEqual(defaults.data(forKey: HabitListStore.storageKey), habitContentBefore)
        XCTAssertEqual(try count(TaskRecord.self, in: container), 3)
    }

    func testPublishStoresBuiltAfterImportPublishAtTheSeededRevision() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)
        try seedWatchLink(defaults, base: TaskListStore.storageKey, revision: 111)
        try seedWatchLink(defaults, base: HabitListStore.storageKey, revision: 222)

        makeImport(defaults, container).run()

        let taskTransport = ControllableTaskTransport()
        let taskList = makeTaskList(defaults, container, sync: .publish(to: taskTransport))
        let taskSnapshot = try XCTUnwrap(taskTransport.published.last)
        XCTAssertEqual(taskSnapshot.revision, 111)
        XCTAssertEqual(taskSnapshot.tasks, taskList.tasks)
        XCTAssertEqual(taskSnapshot.tasks.map(\.text), ["Open", "Also open", "Finished"])

        let habitTransport = ControllableHabitTransport()
        let habitList = makeHabitList(defaults, container, sync: .publish(to: habitTransport))
        let habitSnapshot = try XCTUnwrap(habitTransport.published.last)
        XCTAssertEqual(habitSnapshot.revision, 222)
        XCTAssertEqual(habitSnapshot.habits, habitList.habits)
        XCTAssertEqual(habitSnapshot.habits.map(\.name), ["Run", "Gym", "Read"])
    }

    // MARK: Failure and retry

    func testFailedSaveRollsBackLeavesTheFlagUnsetAndTheKeysIntact() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)
        let taskContent = try XCTUnwrap(defaults.data(forKey: TaskListStore.storageKey))
        let habitContent = try XCTUnwrap(defaults.data(forKey: HabitListStore.storageKey))

        let outcome = makeImport(defaults, container, save: { _ in throw SaveFailure() }).run()

        XCTAssertEqual(outcome, .failed)
        XCTAssertFalse(isDone(defaults))
        XCTAssertEqual(defaults.data(forKey: TaskListStore.storageKey), taskContent)
        XCTAssertEqual(defaults.data(forKey: HabitListStore.storageKey), habitContent)
        XCTAssertFalse(container.mainContext.hasChanges)
        XCTAssertEqual(try count(TaskRecord.self, in: container), 0)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 0)
        XCTAssertTrue(makeTaskList(defaults, container).tasks.isEmpty)
        XCTAssertTrue(makeHabitList(defaults, container).habits.isEmpty)
    }

    func testRetryAfterAFailedSaveImportsEverything() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)
        makeImport(defaults, container, save: { _ in throw SaveFailure() }).run()

        XCTAssertEqual(makeImport(defaults, container).run(), .imported)

        XCTAssertTrue(isDone(defaults))
        XCTAssertEqual(makeTaskList(defaults, container).tasks, expectedTasks)
        XCTAssertEqual(makeHabitList(defaults, container).habits.map(\.name), ["Run", "Gym", "Read"])
        XCTAssertEqual(try count(TaskRecord.self, in: container), 3)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 3)
    }

    func testImportSavesOnce() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)
        var saves = 0

        makeImport(defaults, container, save: { context in
            saves += 1
            try context.save()
        }).run()

        XCTAssertEqual(saves, 1)
    }

    // MARK: Duplicates

    func testRunningTwiceCreatesNoDuplicates() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)

        XCTAssertEqual(makeImport(defaults, container).run(), .imported)
        XCTAssertEqual(makeImport(defaults, container).run(), .alreadyDone)

        XCTAssertEqual(try count(TaskRecord.self, in: container), 3)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 3)
        XCTAssertEqual(try count(HabitCheckOffRecord.self, in: container), 6)
        XCTAssertEqual(try count(HabitScheduleRecord.self, in: container), 5)
    }

    func testRerunAfterACrashBeforeTheFlagCreatesNoDuplicates() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        try seedLegacy(defaults)
        makeImport(defaults, container).run()
        defaults.removeObject(forKey: UserDefaultsImport.doneKey)   // the save landed, the flag didn't

        XCTAssertEqual(makeImport(defaults, container).run(), .imported)

        XCTAssertTrue(isDone(defaults))
        XCTAssertEqual(try count(TaskRecord.self, in: container), 3)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 3)
        XCTAssertEqual(try count(HabitCheckOffRecord.self, in: container), 6)
        XCTAssertEqual(try count(HabitScheduleRecord.self, in: container), 5)
        XCTAssertEqual(makeTaskList(defaults, container).tasks, expectedTasks)
    }

    func testItemsAlreadyInTheStoreAreSkippedAndKeepTheirContent() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        let tasks = legacyTasks
        let habits = legacyHabits
        try seedLegacy(defaults, tasks: tasks, habits: habits)
        // An earlier, partial run left one task and one habit behind, since edited.
        container.mainContext.insert(TaskRecord(task: DailyTask(id: tasks[0].id, text: "Edited since", creationOrder: 0)))
        SwiftDataHabitContent.insert(habits[1].withName("Run, edited"), into: container.mainContext)
        try container.mainContext.save()

        makeImport(defaults, container).run()

        XCTAssertEqual(try count(TaskRecord.self, in: container), 3)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 3)
        XCTAssertEqual(makeTaskList(defaults, container).tasks.map(\.text), ["Edited since", "Also open", "Finished"])
        XCTAssertEqual(makeHabitList(defaults, container).habits.map(\.name), ["Run, edited", "Gym", "Read"])
    }

    func testRepeatedIDsWithinTheLegacyDataImportOnce() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        let task = DailyTask(text: "Twice", creationOrder: 0)
        let habit = Habit(name: "Twice", order: 0, createdOn: day(1))
        try seedLegacy(defaults, tasks: [task, task], habits: [habit, habit])

        makeImport(defaults, container).run()

        XCTAssertEqual(try count(TaskRecord.self, in: container), 1)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 1)
    }

    // MARK: Missing, undecodable and done

    func testMissingKeysImportNothingAndSetTheFlag() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()

        XCTAssertEqual(makeImport(defaults, container).run(), .imported)

        XCTAssertTrue(isDone(defaults))
        XCTAssertEqual(try count(TaskRecord.self, in: container), 0)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 0)
        XCTAssertNil(defaults.object(forKey: TaskListStore.storageKey))
        XCTAssertNil(defaults.object(forKey: HabitListStore.storageKey))
    }

    func testUndecodableKeysImportNothingAndSetTheFlag() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: TaskListStore.storageKey)
        defaults.set(garbage, forKey: HabitListStore.storageKey)

        XCTAssertEqual(makeImport(defaults, container).run(), .imported)

        XCTAssertTrue(isDone(defaults))
        XCTAssertEqual(try count(TaskRecord.self, in: container), 0)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 0)
        XCTAssertEqual(defaults.data(forKey: TaskListStore.storageKey), garbage)
        XCTAssertEqual(defaults.data(forKey: HabitListStore.storageKey), garbage)
        XCTAssertTrue(makeTaskList(defaults, container).tasks.isEmpty)
    }

    func testAnUndecodableKeyDoesNotStopTheOtherFromImporting() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        defaults.set(Data("not json".utf8), forKey: TaskListStore.storageKey)
        defaults.set(try JSONEncoder().encode(legacyHabits), forKey: HabitListStore.storageKey)

        XCTAssertEqual(makeImport(defaults, container).run(), .imported)

        XCTAssertEqual(try count(TaskRecord.self, in: container), 0)
        XCTAssertEqual(makeHabitList(defaults, container).habits.map(\.name), ["Run", "Gym", "Read"])
    }

    func testNothingHappensOnceTheFlagIsSet() throws {
        let defaults = try makeDefaults()
        let container = try makeContainer()
        makeImport(defaults, container).run()
        try seedLegacy(defaults)

        XCTAssertEqual(makeImport(defaults, container).run(), .alreadyDone)

        XCTAssertEqual(try count(TaskRecord.self, in: container), 0)
        XCTAssertEqual(try count(HabitRecord.self, in: container), 0)
    }

    func testFlagKeyIsTheDocumentedOne() {
        XCTAssertEqual(UserDefaultsImport.doneKey, "kyo.swiftDataImport.v1.done")
    }
}
