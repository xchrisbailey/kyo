import SwiftData
import XCTest

@MainActor
final class TaskStoragePersistenceTests: XCTestCase {
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
