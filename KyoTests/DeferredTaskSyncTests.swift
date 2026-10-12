import SwiftData
import XCTest

@MainActor
final class DeferredTaskSyncTests: XCTestCase {
    func testInitialAndMutationSnapshotsKeepFutureTasksForOfflineWatchRollover() throws {
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        let transport = ControllableTaskTransport()
        let container = try KyoModelContainer.make(inMemory: true)
        let phoneDefaults = defaults()
        let watchDefaults = defaults()
        let phone = TaskListStore(userDefaults: phoneDefaults, modelContainer: container,
                                  now: { now }, calendar: calendar, sync: .publish(to: transport))
        let watch = TaskListStore(userDefaults: watchDefaults, now: { now }, calendar: calendar,
                                  sync: .mirror(from: transport))
        let task = try XCTUnwrap(phone.addTask(text: "Friday task"))
        let deferred = try XCTUnwrap(phone.deferTask(id: task.id, to: friday))
        XCTAssertTrue(watch.tasks.isEmpty)
        let unrelated = try XCTUnwrap(phone.addTask(text: "Today"))
        _ = phone.editTask(id: unrelated.id, text: "Today renamed")
        XCTAssertEqual(watch.laterTasks, [deferred])
        let restartedPhone = TaskListStore(userDefaults: phoneDefaults, modelContainer: container,
                                           now: { now }, calendar: calendar, sync: .publish(to: transport))
        XCTAssertEqual(restartedPhone.laterTasks, [deferred])
        XCTAssertEqual(watch.laterTasks, [deferred])
        let offline = ControllableTaskTransport()
        offline.disconnect()
        let restartedWatch = TaskListStore(userDefaults: watchDefaults, now: { now }, calendar: calendar,
                                           sync: .mirror(from: offline))
        now = friday
        restartedWatch.refreshForCurrentDay()
        XCTAssertEqual(restartedWatch.tasks.map(\.id), [task.id, unrelated.id])
        XCTAssertEqual(restartedWatch.taskCount, 2)
        XCTAssertTrue(restartedWatch.laterTasks.isEmpty)
    }

    func testPendingWatchRenameReplayAndAcknowledgmentPreserveNewPhonePlannedDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        let transport = ControllableTaskTransport()
        let phone = TaskListStore(userDefaults: defaults(), modelContainer: try KyoModelContainer.make(inMemory: true),
                                  now: { now }, calendar: calendar, sync: .publish(to: transport))
        let watchDefaults = defaults()
        let watch = TaskListStore(userDefaults: watchDefaults, now: { now }, calendar: calendar,
                                  sync: .mirror(from: transport))
        let task = try XCTUnwrap(phone.addTask(text: "Original"))
        transport.disconnect()
        _ = watch.editTask(id: task.id, text: "Renamed offline")
        let deferred = try XCTUnwrap(phone.deferTask(id: task.id, to: friday))
        transport.deliver(try XCTUnwrap(transport.published.last))
        XCTAssertTrue(watch.tasks.isEmpty)
        XCTAssertEqual(watch.laterTasks.first?.text, "Renamed offline")
        XCTAssertEqual(watch.laterTasks.first?.plannedOn, deferred.plannedOn)
        transport.reconnect()
        XCTAssertEqual(phone.laterTasks, watch.laterTasks)
        XCTAssertEqual(phone.laterTasks.first?.creationOrder, task.creationOrder)
        let command = try XCTUnwrap(transport.sentCommands.last)
        transport.redeliver(command)
        now = friday
        watch.refreshForCurrentDay()
        phone.refreshForCurrentDay()
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(watch.tasks.map(\.text), ["Renamed offline"])
        XCTAssertEqual(watch.tasks.first?.plannedOn, deferred.plannedOn)
    }

    func testPendingWatchCompletionAndReopeningPreservePlannedDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        let transport = ControllableTaskTransport()
        let phone = TaskListStore(userDefaults: defaults(), modelContainer: try KyoModelContainer.make(inMemory: true),
                                  now: { today }, calendar: calendar, sync: .publish(to: transport))
        let watch = TaskListStore(userDefaults: defaults(), now: { today }, calendar: calendar,
                                  sync: .mirror(from: transport))
        let task = try XCTUnwrap(phone.addTask(text: "Pending completion"))
        transport.disconnect()
        _ = watch.toggleTask(id: task.id)
        let deferred = try XCTUnwrap(phone.deferTask(id: task.id, to: friday))
        transport.deliver(try XCTUnwrap(transport.published.last))
        XCTAssertEqual(watch.tasks.first?.plannedOn, deferred.plannedOn)
        transport.reconnect()
        XCTAssertEqual(phone.tasks.first?.plannedOn, deferred.plannedOn)
        XCTAssertEqual(phone.tasks.first?.completedOn, TaskCompletionDay(date: today, calendar: calendar))
        _ = watch.toggleTask(id: task.id)
        XCTAssertTrue(phone.tasks.isEmpty)
        XCTAssertTrue(watch.tasks.isEmpty)
        XCTAssertEqual(watch.laterTasks, phone.laterTasks)
        XCTAssertEqual(watch.laterTasks.first?.plannedOn, deferred.plannedOn)
    }

    private func defaults() -> UserDefaults {
        let name = "DeferredTaskSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
