import SwiftData
import XCTest

@MainActor
final class WatchProjectTaskSyncTests: XCTestCase {
    func testDiskAndCacheRestartRetryPreservesNewerProjectMetadataAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let suite = "WatchProjectTaskSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let transport = ControllableTaskTransport()
        var project: Project!
        var completed: DailyTask!
        var deleted: DailyTask!
        var staleSnapshot: TaskListSnapshot!
        var commands: [TaskCommand] = []
        do {
            let container = try KyoModelContainer.make(storeURL: url)
            let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
                                      now: { now }, calendar: calendar, sync: .publish(to: transport))
            let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: phone)
            project = try XCTUnwrap(projects.createProject(name: "Kyo"))
            completed = try XCTUnwrap(projects.addTaskForToday(text: "Complete offline", to: project.id))
            deleted = try XCTUnwrap(projects.addTaskForToday(text: "Delete offline", to: project.id))
            _ = try XCTUnwrap(projects.addTask(text: "Unchosen", to: project.id))
            let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now }, calendar: calendar,
                                      sync: .mirror(from: transport))
            staleSnapshot = try XCTUnwrap(transport.published.last)
            transport.disconnect()
            _ = watch.editTask(id: completed.id, text: "Edited offline")
            _ = watch.toggleTask(id: completed.id)
            _ = watch.deleteTask(id: deleted.id)
            commands = transport.sentCommands
            _ = projects.renameProject(id: project.id, name: "Build Kyo")
            _ = phone.deferTask(id: completed.id, to: tomorrow)
        }
        let restart = ControllableTaskTransport()
        restart.disconnect()
        let container = try KyoModelContainer.make(storeURL: url)
        let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
                                  now: { now }, calendar: calendar, sync: .publish(to: restart))
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now }, calendar: calendar,
                                  sync: .mirror(from: restart))
        XCTAssertEqual(watch.tasks.map(\.text), ["Edited offline"])
        XCTAssertEqual(watch.completedCount, 1)
        XCTAssertEqual(watch.projectCatalog.first?.name, "Kyo")
        restart.reconnect()
        XCTAssertEqual(watch.tasks, phone.tasks)
        let task = try XCTUnwrap(phone.tasks.first)
        XCTAssertEqual(task.id, completed.id)
        XCTAssertEqual(task.creationOrder, completed.creationOrder)
        XCTAssertEqual(task.projectID, project.id)
        XCTAssertEqual(task.plannedOn, TaskPlannedDay(era: 1, year: 2026, month: 10, day: 13))
        XCTAssertFalse(task.isUnscheduled)
        XCTAssertTrue(task.isComplete)
        XCTAssertEqual(watch.projectCatalog.first?.name, "Build Kyo")
        XCTAssertFalse(phone.tasks(in: project.id).contains { $0.id == deleted.id })
        _ = phone.editTask(id: task.id, text: "Phone final text")
        commands.forEach(restart.redeliver)
        restart.deliver(staleSnapshot)
        XCTAssertEqual(watch.projectCatalog.first?.name, "Build Kyo")
        XCTAssertEqual(watch.tasks.first?.text, "Phone final text")
        XCTAssertEqual(watch.tasks, phone.tasks)
        let offline = ControllableTaskTransport()
        offline.disconnect()
        let cached = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now }, calendar: calendar,
                                   sync: .mirror(from: offline))
        XCTAssertTrue(offline.sentCommands.isEmpty, "Acknowledged outbox must not replay after restart")
        now = tomorrow
        cached.refreshForCurrentDay()
        XCTAssertTrue(cached.tasks.isEmpty, "Yesterday's completion must leave Today")
        _ = phone.toggleTask(id: task.id)
        XCTAssertNil(phone.tasks.first?.plannedOn)
        XCTAssertEqual(phone.tasks.first?.projectID, project.id)
        XCTAssertFalse(try XCTUnwrap(phone.tasks.first).isUnscheduled)
        let finalTransport = ControllableTaskTransport()
        let reopenedPhone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
                                          now: { now }, calendar: calendar, sync: .publish(to: finalTransport))
        let reopenedWatch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now }, calendar: calendar,
                                          sync: .mirror(from: finalTransport))
        commands.forEach(finalTransport.redeliver)
        finalTransport.send(TaskCommand(id: UUID(), action: .add(taskID: deleted.id, text: "Stale resurrection")))
        XCTAssertEqual(reopenedWatch.tasks, reopenedPhone.tasks)
        XCTAssertEqual(reopenedPhone.tasks.map(\.id), [completed.id])
        XCTAssertEqual(reopenedWatch.everydayTasks, [])
    }
}
