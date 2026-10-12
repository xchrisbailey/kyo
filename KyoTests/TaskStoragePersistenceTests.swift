import SwiftData
import XCTest

@MainActor
final class TaskStoragePersistenceTests: XCTestCase {
    private enum PrePlannedSchema: VersionedSchema {
        static let versionIdentifier = Schema.Version(2, 0, 0)
        static var models: [any PersistentModel.Type] {
            [PrePlannedTaskSchema.TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self,
             HabitScheduleRecord.self, MemoRecord.self, MemoAudioRecord.self, MemoPhotoRecord.self]
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
            _ = MemoStore(modelContainer: old).addWrittenMemo(text: "Remember before upgrade")
        }
        let container = try KyoModelContainer.make(storeURL: url)
        let list = TaskListStore(modelContainer: container, now: { today }, calendar: calendar)
        XCTAssertEqual(list.tasks.map(\.text), ["Ordinary", "Completed before upgrade"])
        XCTAssertTrue(list.tasks.allSatisfy { $0.plannedOn == nil })
        XCTAssertEqual(list.tasksCompleted(on: today), [completed])
        XCTAssertEqual(SwiftDataHabitContent(modelContainer: container).load().map(\.name), ["Stretch"])
        XCTAssertEqual(MemoStore(modelContainer: container).memos.map(\.title), ["Remember before upgrade"])
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
