import SwiftData
import XCTest

@MainActor
final class ProjectListBehaviorTests: XCTestCase {
    func testChoosingAndReturningProjectWorkKeepsIdentityAndEverydayCountsDisjoint() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let tasks = TaskListStore(modelContainer: container)
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let task = try XCTUnwrap(projects.addTask(text: "Widgets", to: project.id))
        let everyday = try XCTUnwrap(tasks.addTask(text: "Groceries"))
        XCTAssertEqual(projects.todayProjects, [])
        let chosen = try XCTUnwrap(projects.doToday(taskID: task.id))
        XCTAssertEqual(chosen.id, task.id)
        XCTAssertFalse(chosen.isUnscheduled)
        XCTAssertEqual(tasks.everydayTasks, [everyday])
        XCTAssertEqual(projects.todayTasks(in: project.id), [chosen])
        XCTAssertEqual(projects.todayProjects, [project])
        XCTAssertEqual(tasks.taskCount, 2)
        XCTAssertEqual(tasks.incompleteCount, 2)
        let returned = try XCTUnwrap(projects.returnToProject(taskID: task.id))
        XCTAssertEqual(returned.id, task.id)
        XCTAssertTrue(returned.isUnscheduled)
        XCTAssertEqual(projects.unscheduledTasks(in: project.id), [returned])
        XCTAssertEqual(projects.todayProjects, [])
        XCTAssertEqual(tasks.tasks, [everyday])
    }

    func testTodayPartitionsCarryForwardAndCompletedHistoryReopensOnToday() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let tasks = TaskListStore(modelContainer: container, now: { now }, calendar: calendar)
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        let first = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let second = try XCTUnwrap(projects.createProject(name: "House"))
        let done = try XCTUnwrap(projects.addTaskForToday(text: "Widgets", to: first.id))
        let unfinished = try XCTUnwrap(projects.addTaskForToday(text: "Sync", to: first.id))
        let secondDone = try XCTUnwrap(projects.addTaskForToday(text: "Paint", to: second.id))
        _ = tasks.toggleTask(id: done.id)
        _ = tasks.toggleTask(id: secondDone.id)
        XCTAssertNil(projects.returnToProject(taskID: done.id))
        XCTAssertEqual(projects.todayTasks(in: first.id).map(\.id), [unfinished.id, done.id])
        XCTAssertEqual(projects.todayProjects.map(\.id), [first.id, second.id])
        XCTAssertEqual(tasks.completedCount, 2)
        now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        tasks.refreshForCurrentDay()
        XCTAssertEqual(projects.todayProjects.map(\.id), [first.id])
        XCTAssertEqual(projects.todayTasks(in: first.id).map(\.id), [unfinished.id])
        XCTAssertEqual(projects.completedTasks(in: second.id).map(\.id), [secondDone.id])
        _ = tasks.toggleTask(id: secondDone.id)
        XCTAssertEqual(projects.todayProjects.map(\.id), [first.id, second.id])
        XCTAssertEqual(projects.todayTasks(in: second.id).first?.id, secondDone.id)
        XCTAssertFalse(try XCTUnwrap(projects.todayTasks(in: second.id).first).isUnscheduled)
        let unscheduled = try XCTUnwrap(projects.addTask(text: "Future thought", to: first.id))
        _ = tasks.toggleTask(id: unscheduled.id)
        _ = tasks.toggleTask(id: unscheduled.id)
        XCTAssertTrue(projects.todayTasks(in: first.id).contains { $0.id == unscheduled.id })
    }

    func testProjectCatalogRoundTripsRenameAndQueuedCommandsThroughWatchCache() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let transport = ControllableTaskTransport()
        let suite = "ProjectsCatalog.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container, sync: .publish(to: transport))
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: phone)
        let first = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let second = try XCTUnwrap(projects.createProject(name: "House"))
        let task = try XCTUnwrap(projects.addTaskForToday(text: "Widgets", to: first.id))
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", sync: .mirror(from: transport))
        XCTAssertEqual(watch.projectCatalog, [first, second])
        transport.disconnect()
        _ = watch.editTask(id: task.id, text: "Build widgets")
        _ = watch.toggleTask(id: task.id)
        let renamed = try XCTUnwrap(projects.renameProject(id: first.id, name: "Build Kyo"))
        transport.reconnect()
        XCTAssertEqual(watch.projectCatalog, [renamed, second])
        XCTAssertEqual(watch.tasks.first?.projectID, first.id)
        XCTAssertEqual(watch.tasks.first?.text, "Build widgets")
        XCTAssertEqual(watch.tasks.first?.isUnscheduled, false)
        XCTAssertEqual(watch.tasks.first?.isComplete, true)
        let reopened = TaskListStore(userDefaults: defaults, storageKey: "watch", sync: .mirror(from: ControllableTaskTransport()))
        XCTAssertEqual(reopened.projectCatalog, [renamed, second])
        XCTAssertEqual(reopened.tasks, watch.tasks)
        let legacy = Data("{\"revision\":1,\"tasks\":[]}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(TaskListSnapshot.self, from: legacy).projects, [])
    }

    func testWatchCompletionStateDoesNotChooseAlreadyUnfinishedReturnedWork() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let transport = ControllableTaskTransport()
        let suite = "ProjectsReturnedCommand.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let phone = TaskListStore(userDefaults: defaults, modelContainer: container, now: { now }, calendar: calendar,
                                  sync: .publish(to: transport))
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: phone)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let task = try XCTUnwrap(projects.addTaskForToday(text: "Widgets", to: project.id))
        _ = projects.returnToProject(taskID: task.id)
        transport.redeliver(TaskCommand(id: UUID(), action: .setCompletion(taskID: task.id, isComplete: false, completedOn: nil)))
        XCTAssertEqual(projects.unscheduledTasks(in: project.id).map(\.id), [task.id])
        XCTAssertEqual(projects.todayProjects, [])
        _ = projects.doToday(taskID: task.id)
        _ = phone.toggleTask(id: task.id)
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now }, calendar: calendar,
                                  sync: .mirror(from: transport))
        transport.disconnect()
        _ = watch.toggleTask(id: task.id)
        _ = phone.toggleTask(id: task.id)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        _ = phone.deferTask(id: task.id, to: tomorrow)
        transport.deliver(try XCTUnwrap(transport.published.last))
        XCTAssertTrue(watch.tasks.isEmpty)
        XCTAssertEqual(watch.laterTasks.first?.plannedOn, TaskPlannedDay(date: tomorrow, calendar: calendar))
        transport.reconnect()
        XCTAssertTrue(phone.tasks.isEmpty)
        XCTAssertEqual(phone.laterTasks, watch.laterTasks)
        XCTAssertEqual(watch.laterTasks.first?.projectID, project.id)
    }

    func testQueuedCompletionAfterReturnStillAppearsTodayAndRetainsHistory() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let transport = ControllableTaskTransport()
        let suite = "ProjectsQueuedCompletion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
                                  now: { now }, calendar: calendar, sync: .publish(to: transport))
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: phone)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let task = try XCTUnwrap(projects.addTaskForToday(text: "Widgets", to: project.id))
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now }, calendar: calendar,
                                  sync: .mirror(from: transport))
        transport.disconnect()
        _ = watch.toggleTask(id: task.id)
        _ = projects.returnToProject(taskID: task.id)
        transport.reconnect()
        XCTAssertEqual(projects.todayProjects, [project])
        XCTAssertEqual(projects.todayTasks(in: project.id).map(\.id), [task.id])
        XCTAssertEqual(phone.taskCount, 1)
        XCTAssertEqual(phone.completedCount, 1)
        XCTAssertTrue(phone.everydayTasks.isEmpty)
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(phone.tasksCompleted(on: now).map(\.id), [task.id])
        XCTAssertEqual(projects.completedTasks(in: project.id).map(\.id), [task.id])
        let completed = try XCTUnwrap(phone.tasks.first)
        XCTAssertTrue(completed.isUnscheduled)
        XCTAssertTrue(completed.isComplete)
        now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        phone.refreshForCurrentDay()
        watch.refreshForCurrentDay()
        XCTAssertTrue(projects.todayProjects.isEmpty)
        XCTAssertTrue(watch.tasks.isEmpty)
        XCTAssertEqual(projects.completedTasks(in: project.id), [completed])
        _ = phone.toggleTask(id: task.id)
        XCTAssertEqual(projects.todayTasks(in: project.id).map(\.id), [task.id])
        XCTAssertFalse(try XCTUnwrap(phone.tasks.first).isUnscheduled)
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    func testCreationAndRenameKeepIdentityAndCreationOrderWhenReopened() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let tasks = TaskListStore(modelContainer: container)
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        XCTAssertNil(projects.createProject(name: " \n "))
        let first = try XCTUnwrap(projects.createProject(name: " Kyo "))
        let second = try XCTUnwrap(projects.createProject(name: "House"))
        XCTAssertNil(projects.renameProject(id: first.id, name: " "))
        _ = projects.renameProject(id: first.id, name: "Build Kyo")
        let reopened: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        XCTAssertEqual(reopened.projects.map(\.name), ["Build Kyo", "House"])
        XCTAssertEqual(reopened.projects.map(\.id), [first.id, second.id])
    }

    func testProjectCaptureRemainsUnscheduledAcrossDayRolloverAndEdits() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let tasks = TaskListStore(modelContainer: container, now: { now }, calendar: calendar)
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        XCTAssertNil(projects.addTask(text: "Orphan", to: UUID()))
        let taskBehavior: any TaskListBehavior = tasks
        XCTAssertNil(taskBehavior.addUnscheduledTask(text: "Orphan", projectID: UUID()))
        let task = try XCTUnwrap(projects.addTask(text: " Explore widgets ", to: project.id))
        XCTAssertTrue(tasks.tasks.isEmpty)
        XCTAssertTrue(tasks.laterTasks.isEmpty)
        XCTAssertEqual(tasks.taskCount, 0)
        XCTAssertNil(task.plannedOn)
        _ = tasks.editTask(id: task.id, text: "Build widgets")
        now = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: now))
        tasks.refreshForCurrentDay()
        XCTAssertTrue(tasks.tasks.isEmpty)
        XCTAssertTrue(tasks.tasksPlanned(on: now).isEmpty)
        XCTAssertTrue(tasks.tasksCompleted(on: now).isEmpty)
        let stored = try XCTUnwrap(projects.unscheduledTasks(in: project.id).first)
        XCTAssertEqual(stored.id, task.id)
        XCTAssertEqual(stored.text, "Build widgets")
        XCTAssertEqual(stored.projectID, project.id)
        XCTAssertEqual(stored.isUnscheduled, true)
        _ = tasks.deleteTask(id: task.id)
        XCTAssertTrue(projects.unscheduledTasks(in: project.id).isEmpty)
    }

    func testProjectsAndUnscheduledTasksSurviveDiskReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        var projectID: UUID?
        var captured: DailyTask?
        do {
            let container = try KyoModelContainer.make(storeURL: url)
            let tasks = TaskListStore(modelContainer: container)
            let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
            let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
            projectID = project.id
            _ = projects.renameProject(id: project.id, name: "Build Kyo")
            captured = try XCTUnwrap(projects.addTask(text: "Explore widgets", to: project.id))
        }
        let container = try KyoModelContainer.make(storeURL: url)
        let tasks = TaskListStore(modelContainer: container)
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        XCTAssertEqual(projects.projects.map(\.name), ["Build Kyo"])
        XCTAssertEqual(projects.projects.first?.id, projectID)
        XCTAssertEqual(projects.unscheduledTasks(in: try XCTUnwrap(projectID)), [try XCTUnwrap(captured)])
        XCTAssertTrue(tasks.tasks.isEmpty)
        XCTAssertTrue(tasks.laterTasks.isEmpty)
    }

    func testUnscheduledCaptureIsAbsentFromWatchAndMonthWhileEverydayTasksRemainAvailable() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let transport = ControllableTaskTransport()
        let suite = "ProjectsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try KyoModelContainer.make(inMemory: true)
        let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
                                  now: { now }, calendar: calendar, sync: .publish(to: transport))
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now }, calendar: calendar,
                                  sync: .mirror(from: transport))
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: phone)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        _ = projects.addTask(text: "Eventual work", to: project.id)
        let everyday = try XCTUnwrap(phone.addTask(text: "Groceries"))
        XCTAssertEqual(watch.tasks, [everyday])
        XCTAssertTrue(watch.tasks(in: project.id).isEmpty)
        XCTAssertTrue(phone.tasksPlanned(on: now).isEmpty)
        XCTAssertTrue(phone.tasksCompleted(on: now).isEmpty)
        XCTAssertEqual(phone.taskCount, 1)
    }

    func testLegacyWatchCacheRetainsEverydayAvailabilityAndPendingEdits() throws {
        let suite = "ProjectsLegacyCache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let oldCache = Data("""
        [{"id":"00000000-0000-0000-0000-000000000001","text":"Groceries","creationOrder":0,"isComplete":false}]
        """.utf8)
        defaults.set(oldCache, forKey: "watch")
        let command = TaskCommand(id: UUID(), action: .rename(taskID: id, text: "Buy groceries"))
        defaults.set(try JSONEncoder().encode([command]), forKey: "watch.outbox")
        let transport = ControllableTaskTransport()
        transport.disconnect()
        let watch: any TaskListBehavior = TaskListStore(userDefaults: defaults, storageKey: "watch", sync: .mirror(from: transport))
        XCTAssertEqual(watch.tasks.map(\.text), ["Buy groceries"])
        XCTAssertEqual(watch.tasks.first?.id, id)
        XCTAssertNil(watch.tasks.first?.projectID)
        XCTAssertEqual(watch.tasks.first?.isUnscheduled, false)
        let reopened: any TaskListBehavior = TaskListStore(userDefaults: defaults, storageKey: "watch", sync: .mirror(from: transport))
        XCTAssertEqual(reopened.tasks, watch.tasks)
    }

    func testPhoneActionsAndQueuedWatchCommandsPreserveProjectMetadata() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let transport = ControllableTaskTransport()
        let suite = "ProjectsReplay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let phone = TaskListStore(userDefaults: defaults, modelContainer: container, now: { now }, calendar: calendar,
                                  sync: .publish(to: transport))
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: phone)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let task = try XCTUnwrap(projects.addTask(text: "Explore widgets", to: project.id))
        _ = phone.toggleTask(id: task.id)
        _ = phone.toggleTask(id: task.id)
        let future = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: now))
        _ = phone.deferTask(id: task.id, to: future)
        _ = phone.bringTaskToToday(id: task.id)
        transport.redeliver(TaskCommand(id: UUID(), action: .rename(taskID: task.id, text: "Queued edit")))
        transport.redeliver(TaskCommand(id: UUID(), action: .setCompletion(taskID: task.id, isComplete: true,
                                                                         completedOn: TaskCompletionDay(date: now, calendar: calendar))))
        let stored = try XCTUnwrap(phone.tasks(in: project.id).first)
        XCTAssertEqual(stored.projectID, project.id)
        XCTAssertFalse(stored.isUnscheduled)
        XCTAssertTrue(stored.isComplete)
        XCTAssertEqual(stored.text, "Queued edit")
        XCTAssertEqual(stored.id, task.id)
        XCTAssertEqual(stored.creationOrder, task.creationOrder)
        let reopened: any TaskListBehavior = TaskListStore(modelContainer: container)
        XCTAssertEqual(reopened.tasks(in: project.id), [stored])
    }

    func testWatchReplayPreservesProjectAssociationAndAvailability() throws {
        let suite = "ProjectsWatchReplay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = ControllableTaskTransport()
        let projectID = UUID()
        let task = DailyTask(text: "Chosen work", creationOrder: 0, projectID: projectID)
        transport.publish(TaskListSnapshot(revision: 1, tasks: [task]))
        let watch: any TaskListBehavior = TaskListStore(userDefaults: defaults, sync: .mirror(from: transport))
        _ = watch.editTask(id: task.id, text: "Edited on Watch")
        _ = watch.toggleTask(id: task.id)
        let edited = try XCTUnwrap(watch.tasks.first)
        XCTAssertEqual(edited.projectID, projectID)
        XCTAssertFalse(edited.isUnscheduled)
        XCTAssertEqual(edited.text, "Edited on Watch")
        XCTAssertTrue(edited.isComplete)
        let reopened: any TaskListBehavior = TaskListStore(userDefaults: defaults, sync: .mirror(from: transport))
        XCTAssertEqual(reopened.tasks, [edited])
    }
}
