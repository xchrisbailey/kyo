import SwiftData
import XCTest

@MainActor
final class TaskStoragePersistenceTests: XCTestCase {
    private enum PrePlannedSchema: VersionedSchema {
        static let versionIdentifier = Schema.Version(2, 0, 0)
        static var models: [any PersistentModel.Type] {
            [PrePlannedTaskSchema.TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self,
             HabitScheduleRecord.self, PreProjectMemoSchema.MemoRecord.self, PreProjectMemoSchema.MemoAudioRecord.self, PreProjectMemoSchema.MemoPhotoRecord.self]
        }
    }

    func testInstalledPrePlannedDayDatabaseUpgradesWithoutLosingTaskCompletionOrOtherContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let completed = DailyTask(text: "Completed before upgrade", creationOrder: 1, isComplete: true,
                                  completedOn: TaskCompletionDay(date: today, calendar: calendar))
        do {
            let schema = Schema(versionedSchema: PrePlannedSchema.self)
            let old = try ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            old.mainContext.insert(PrePlannedTaskSchema.TaskRecord(task: DailyTask(text: "Ordinary", creationOrder: 0)))
            old.mainContext.insert(PrePlannedTaskSchema.TaskRecord(task: completed))
            try old.mainContext.save()
            SwiftDataHabitContent(modelContainer: old).save([Habit(name: "Stretch", order: 0)])
            old.mainContext.insert(PreProjectMemoSchema.MemoRecord(kind: .written, createdAt: Date(),
                day: TaskCompletionDay(date: Date(), calendar: calendar), text: "Remember before upgrade"))
            try old.mainContext.save()
        }
        let container = try KyoModelContainer.make(storeURL: url)
        let list = TaskListStore(modelContainer: container, now: { today }, calendar: calendar)
        XCTAssertEqual(list.tasks.map(\.text), ["Ordinary", "Completed before upgrade"])
        XCTAssertTrue(list.tasks.allSatisfy { $0.plannedOn == nil })
        XCTAssertEqual(list.tasksCompleted(on: today), [completed])
        XCTAssertEqual(SwiftDataHabitContent(modelContainer: container).load().map(\.name), ["Stretch"])
        XCTAssertEqual(MemoStore(modelContainer: container).memos.map(\.title), ["Remember before upgrade"])
    }

    func testInstalledPreProjectStorePreservesPlannedDaysCompletionMemosAndMedia() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let future = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: today))
        let ordinary = DailyTask(text: "Groceries", creationOrder: 0)
        let deferred = DailyTask(text: "Call Friday", creationOrder: 1, plannedOn: TaskPlannedDay(date: future, calendar: calendar))
        let completed = DailyTask(text: "Done", creationOrder: 2, isComplete: true,
                                  completedOn: TaskCompletionDay(date: today, calendar: calendar))
        let audio = RecordedAudio(id: UUID(), startedAt: today, duration: 3, data: Data(repeating: 7, count: 150_000))
        let photo = StoredPhoto(id: UUID(), data: Data(repeating: 9, count: 150_000), thumbnail: Data([1, 2]))
        var writtenID: UUID?
        do {
            let schema = Schema(versionedSchema: KyoSchemaV3.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            for task in [ordinary, deferred, completed] { old.mainContext.insert(PreProjectTaskSchema.TaskRecord(task: task)) }
            try old.mainContext.save()
            SwiftDataHabitContent(modelContainer: old).save([Habit(name: "Stretch", order: 0)])
            let written = PreProjectMemoSchema.MemoRecord(kind: .written, createdAt: today,
                day: TaskCompletionDay(date: today, calendar: calendar), text: "Remember this")
            written.photos = [PreProjectMemoSchema.MemoPhotoRecord(id: photo.id, order: 0, data: photo.data, thumbnail: photo.thumbnail)]
            writtenID = written.id
            old.mainContext.insert(written)
            let voice = PreProjectMemoSchema.MemoRecord(id: audio.id, kind: .voice, createdAt: today,
                day: TaskCompletionDay(date: today, calendar: calendar), text: "", durationSeconds: 3, transcriptState: .noTranscript)
            voice.audio = PreProjectMemoSchema.MemoAudioRecord(data: audio.data)
            old.mainContext.insert(voice)
            try old.mainContext.save()
        }
        let container = try KyoModelContainer.make(storeURL: url)
        let tasks: any TaskListBehavior = TaskListStore(modelContainer: container, now: { today }, calendar: calendar)
        XCTAssertEqual(tasks.tasks, [ordinary, completed])
        XCTAssertEqual(tasks.laterTasks, [deferred])
        XCTAssertTrue(tasks.tasks.allSatisfy { $0.projectID == nil && !$0.isUnscheduled })
        XCTAssertEqual(SwiftDataHabitContent(modelContainer: container).load().map(\.name), ["Stretch"])
        let memos: any MemoStoreBehavior = MemoStore(modelContainer: container, now: { today }, calendar: calendar)
        XCTAssertEqual(memos.memo(id: try XCTUnwrap(writtenID))?.text, "Remember this")
        XCTAssertEqual(memos.photoData(forPhotoID: photo.id), photo.data)
        XCTAssertEqual(memos.audioData(forMemoID: audio.id), audio.data)
    }

    func testScheduledCreationSurvivesDiskReopeningWithIdentityTextAndOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        var planned: DailyTask?
        do {
            let container = try KyoModelContainer.make(storeURL: url)
            let list: any TaskListBehavior = TaskListStore(modelContainer: container, now: { today }, calendar: calendar)
            _ = list.addTask(text: "First")
            planned = try XCTUnwrap(list.addTask(text: "Call Friday", plannedFor: friday))
            _ = list.addTask(text: "Third")
        }
        let container = try KyoModelContainer.make(storeURL: url)
        let reopened = TaskListStore(modelContainer: container, now: { today }, calendar: calendar)
        XCTAssertEqual(reopened.laterTasks, [try XCTUnwrap(planned)])
        XCTAssertEqual(reopened.laterTasks.first?.creationOrder, 1)
        XCTAssertEqual(reopened.tasks.map(\.text), ["First", "Third"])
        XCTAssertEqual(reopened.taskCount, 2)
    }

    func testTasksSeededWithTheSameIDLoadOnce() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let id = UUID()
        container.mainContext.insert(TaskRecord(task: DailyTask(id: id, text: "Duplicated", creationOrder: 0)))
        container.mainContext.insert(TaskRecord(task: DailyTask(id: id, text: "Duplicated", creationOrder: 0)))
        container.mainContext.insert(TaskRecord(task: DailyTask(text: "Other", creationOrder: 1)))
        try container.mainContext.save()

        let list = TaskListStore(modelContainer: container)

        XCTAssertEqual(list.tasks.map(\.text), ["Duplicated", "Other"])
        XCTAssertEqual(list.tasks.filter { $0.id == id }.count, 1)
        XCTAssertEqual(TaskListStore(modelContainer: container).tasks, list.tasks)
    }

    func testPhoneStoreLeavesTheTaskContentKeyUntouched() throws {
        let suiteName = "TaskStoragePersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let container = try KyoModelContainer.make(inMemory: true)
        let backup = Data("frozen backup".utf8)
        defaults.set(backup, forKey: TaskListStore.storageKey)

        let phone = TaskListStore(
            userDefaults: defaults,
            modelContainer: container,
            sync: .publish(to: ControllableTaskTransport())
        )
        let task = try XCTUnwrap(phone.addTask(text: "Not in UserDefaults"))
        _ = phone.toggleTask(id: task.id)

        XCTAssertEqual(defaults.data(forKey: TaskListStore.storageKey), backup)
        XCTAssertEqual(phone.tasks.map(\.text), ["Not in UserDefaults"])
    }

    func testStandaloneStoreIgnoresTasksLeftInTheContentKey() throws {
        let suiteName = "TaskStoragePersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(try JSONEncoder().encode([DailyTask(text: "Old backup", creationOrder: 0)]), forKey: TaskListStore.storageKey)

        let list = TaskListStore(userDefaults: defaults, modelContainer: try KyoModelContainer.make(inMemory: true))

        XCTAssertTrue(list.tasks.isEmpty)
    }

    func testDeletedTasksStayDeletedAfterReopening() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let list = TaskListStore(modelContainer: container)
        let kept = try XCTUnwrap(list.addTask(text: "Kept"))
        let removed = try XCTUnwrap(list.addTask(text: "Removed"))
        _ = list.deleteTask(id: removed.id)

        let reopened = TaskListStore(modelContainer: container)

        XCTAssertEqual(reopened.tasks, [kept])
    }
}
