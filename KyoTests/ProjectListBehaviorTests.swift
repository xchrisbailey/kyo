import SwiftData
import XCTest

@MainActor
final class ProjectListBehaviorTests: XCTestCase {
    func testAssignmentPreservesEveryTaskStateAndRemovingUnscheduledMakesEverydayWork() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let future = try XCTUnwrap(calendar.date(byAdding: .day, value: 4, to: now))
        let tasks: TaskListStore = TaskListStore(modelContainer: container, now: { now }, calendar: calendar)
        let behavior: any TaskListBehavior = tasks
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        let first = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let second = try XCTUnwrap(projects.createProject(name: "House"))
        let everyday = try XCTUnwrap(tasks.addTask(text: "Everyday"))
        let deferred = try XCTUnwrap(tasks.addTask(text: "Later", plannedFor: future))
        let chosen = try XCTUnwrap(projects.addTaskForToday(text: "Chosen", to: first.id))
        let unscheduled = try XCTUnwrap(projects.addTask(text: "Unscheduled", to: first.id))
        let completed = try XCTUnwrap(tasks.addTask(text: "Completed"))
        let done = try XCTUnwrap(tasks.toggleTask(id: completed.id))
        let historical = try XCTUnwrap(projects.addTaskForToday(text: "Historical", to: first.id))
        let pastDone = try XCTUnwrap(tasks.toggleTask(id: historical.id))
        now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        tasks.refreshForCurrentDay()
        let todayTask = try XCTUnwrap(tasks.addTask(text: "Completed today"))
        let todayDone = try XCTUnwrap(tasks.toggleTask(id: todayTask.id))
        for original in [everyday, deferred, chosen, unscheduled, done, pastDone, todayDone] {
            let moved = try XCTUnwrap(behavior.assignTask(id: original.id, to: second.id))
            XCTAssertEqual(moved, DailyTask(id: original.id, text: original.text, creationOrder: original.creationOrder,
                                           isComplete: original.isComplete, completedOn: original.completedOn,
                                           plannedOn: original.plannedOn, projectID: second.id, isUnscheduled: original.isUnscheduled))
            XCTAssertEqual(behavior.assignTask(id: original.id, to: second.id), moved)
            let removed = try XCTUnwrap(behavior.assignTask(id: original.id, to: nil))
            XCTAssertEqual(removed, DailyTask(id: original.id, text: original.text, creationOrder: original.creationOrder,
                                             isComplete: original.isComplete, completedOn: original.completedOn,
                                             plannedOn: original.plannedOn))
        }
        XCTAssertEqual(tasks.taskCount, 4)
        XCTAssertEqual(tasks.completedCount, 1)
        XCTAssertEqual(tasks.tasksCompleted(on: now).map(\.id), [todayDone.id])
        XCTAssertEqual(tasks.laterTasks.map(\.id), [deferred.id])
        XCTAssertEqual(tasks.tasksPlanned(on: future, calendar: calendar).map(\.id), [deferred.id])
        XCTAssertTrue(tasks.tasks(in: first.id).isEmpty)
        XCTAssertTrue(tasks.tasks(in: second.id).isEmpty)
        XCTAssertNil(behavior.assignTask(id: everyday.id, to: UUID()))
        XCTAssertNil(behavior.assignTask(id: UUID(), to: second.id))
        XCTAssertEqual(tasks.everydayTasks.map(\.id), [everyday.id, chosen.id, unscheduled.id, todayDone.id])
    }

    func testAssignmentSurvivesDiskReopeningAndQueuedDuplicateWatchCommands() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let suite = "ProjectAssignment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let future = try XCTUnwrap(calendar.date(byAdding: .day, value: 4, to: today))
        let transport = ControllableTaskTransport()
        var expected: DailyTask?
        var projectID: UUID?
        do {
            let container = try KyoModelContainer.make(storeURL: url)
            let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
                                      now: { today }, calendar: calendar, sync: .publish(to: transport))
            let projects = ProjectListStore(modelContainer: container, taskList: phone)
            let first = try XCTUnwrap(projects.createProject(name: "Kyo"))
            let second = try XCTUnwrap(projects.createProject(name: "House"))
            projectID = second.id
            let task = try XCTUnwrap(phone.addTask(text: "Widgets"))
            let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { today }, calendar: calendar,
                                      sync: .mirror(from: transport))
            XCTAssertNil(watch.assignTask(id: task.id, to: first.id))
            transport.disconnect()
            _ = watch.editTask(id: task.id, text: "Edited widgets")
            _ = watch.toggleTask(id: task.id)
            _ = phone.assignTask(id: task.id, to: first.id)
            _ = phone.deferTask(id: task.id, to: future)
            _ = phone.assignTask(id: task.id, to: second.id)
            _ = projects.renameProject(id: second.id, name: "Renamed House")
            transport.reconnect()
            let completion = try XCTUnwrap(transport.sentCommands.last)
            let rename = try XCTUnwrap(transport.sentCommands.first)
            expected = try XCTUnwrap(phone.tasks.first)
            XCTAssertEqual(expected?.projectID, second.id)
            XCTAssertEqual(expected?.plannedOn, TaskPlannedDay(date: future, calendar: calendar))
            XCTAssertEqual(expected?.text, "Edited widgets")
            XCTAssertEqual(expected?.isComplete, true)
            XCTAssertEqual(watch.tasks, phone.tasks)
            XCTAssertEqual(watch.projectCatalog.last?.name, "Renamed House")
            _ = phone.assignTask(id: task.id, to: nil)
            transport.redeliver(rename)
            transport.redeliver(completion)
            XCTAssertNil(phone.tasks.first?.projectID)
            _ = phone.assignTask(id: task.id, to: second.id)
            expected = phone.tasks.first
            XCTAssertEqual(phone.taskCount, 1)
        }
        let reopened = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: try KyoModelContainer.make(storeURL: url),
                                     now: { today }, calendar: calendar)
        XCTAssertEqual(reopened.tasks, [try XCTUnwrap(expected)])
        XCTAssertEqual(reopened.tasks(in: try XCTUnwrap(projectID)), reopened.tasks)
        XCTAssertEqual(reopened.tasksCompleted(on: today), reopened.tasks)
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { today }, calendar: calendar,
                                  sync: .mirror(from: ControllableTaskTransport()))
        XCTAssertEqual(watch.tasks, reopened.tasks)
        XCTAssertEqual(watch.projectCatalog.last?.name, "Renamed House")
    }

    func testSchedulingUnscheduledProjectTaskSelectsLaterAndReturnClearsItsProjection() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        let tasks = TaskListStore(modelContainer: container, now: { today }, calendar: calendar)
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let task = try XCTUnwrap(projects.addTask(text: "Build widgets", to: project.id))
        let deferred = try XCTUnwrap(tasks.deferTask(id: task.id, to: friday))
        XCTAssertFalse(deferred.isUnscheduled)
        XCTAssertEqual(deferred.text, "Build widgets")
        XCTAssertEqual(tasks.laterTasks, [deferred])
        XCTAssertEqual(tasks.tasksPlanned(on: friday, calendar: calendar), [deferred])
        XCTAssertTrue(projects.unscheduledTasks(in: project.id).isEmpty)
        let returned = try XCTUnwrap(projects.returnToProject(taskID: task.id))
        XCTAssertEqual(returned.id, task.id)
        XCTAssertNil(returned.plannedOn)
        XCTAssertTrue(returned.isUnscheduled)
        XCTAssertTrue(tasks.laterTasks.isEmpty)
        XCTAssertTrue(tasks.tasksPlanned(on: friday, calendar: calendar).isEmpty)
        XCTAssertEqual(tasks.taskCount, 0)
    }

    func testExplicitProjectCaptureUsesTodayOrOrderedLaterWithoutCreatingInvalidWork() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let transport = ControllableTaskTransport()
        let suite = "ProjectPlannedCapture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tasks = TaskListStore(userDefaults: defaults, modelContainer: container, now: { today }, calendar: calendar,
                                  sync: .publish(to: transport))
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: tasks)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let unscheduled = try XCTUnwrap(projects.addTask(text: "Eventual", to: project.id))
        let last = try XCTUnwrap(projects.addTask(text: "Monday", to: project.id, plannedFor: monday))
        let first = try XCTUnwrap(projects.addTask(text: "Friday first", to: project.id, plannedFor: friday))
        let second = try XCTUnwrap(projects.addTask(text: "Friday second", to: project.id, plannedFor: friday))
        let chosen = try XCTUnwrap(projects.addTask(text: "Today", to: project.id, plannedFor: today))
        XCTAssertEqual(projects.laterTasks(in: project.id), [first, second, last])
        XCTAssertEqual(projects.todayTasks(in: project.id), [chosen])
        XCTAssertEqual(projects.unscheduledTasks(in: project.id), [unscheduled])
        let snapshot = try XCTUnwrap(transport.published.last)
        XCTAssertNil(projects.addTask(text: "Past", to: project.id, plannedFor: yesterday))
        XCTAssertNil(tasks.addTask(text: "Unknown", projectID: UUID(), plannedFor: friday))
        XCTAssertEqual(transport.published.last, snapshot)
        XCTAssertEqual(tasks.tasks(in: project.id).count, 5)
    }

    func testFutureProjectWorkSurvivesDiskAndOfflineWatchCacheRolloverAcrossZoneChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let suite = "ProjectPlanningCache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Detroit"))
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12)))
        let planned = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let plannedDay = TaskPlannedDay(era: 1, year: 2026, month: 11, day: 1)
        let transport = ControllableTaskTransport()
        var captured: DailyTask?
        var project: Project?
        do {
            let container = try KyoModelContainer.make(storeURL: url)
            let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
                                      now: { now }, calendarProvider: { calendar }, sync: .publish(to: transport))
            let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: phone)
            project = try XCTUnwrap(projects.createProject(name: "Build Kyo"))
            captured = try XCTUnwrap(projects.addTask(text: "DST project work", to: try XCTUnwrap(project).id, plannedFor: planned))
            _ = projects.addTask(text: "Unchosen", to: try XCTUnwrap(project).id)
            let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now },
                                                           calendarProvider: { calendar }, sync: .mirror(from: transport))
            XCTAssertTrue(watch.tasks.isEmpty)
            XCTAssertEqual(watch.laterTasks, [try XCTUnwrap(captured)])
            XCTAssertEqual(watch.projectCatalog, [try XCTUnwrap(project)])
        }
        let container = try KyoModelContainer.make(storeURL: url)
        let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
                                  now: { now }, calendarProvider: { calendar }, sync: .publish(to: transport))
        XCTAssertEqual(phone.laterTasks, [try XCTUnwrap(captured)])
        XCTAssertEqual(transport.published.last?.tasks, [try XCTUnwrap(captured)])
        let offline = ControllableTaskTransport()
        offline.disconnect()
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now },
                                                       calendarProvider: { calendar }, sync: .mirror(from: offline))
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        phone.refreshForCurrentDay()
        watch.refreshForCurrentDay()
        XCTAssertEqual(watch.tasks, [try XCTUnwrap(captured)])
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(watch.tasks.first?.plannedOn, plannedDay)
        XCTAssertEqual(watch.projectCatalog, [try XCTUnwrap(project)])
        now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        watch.refreshForCurrentDay()
        XCTAssertEqual(watch.taskCount, 1)
        XCTAssertTrue(watch.laterTasks.isEmpty)
        XCTAssertEqual(watch.tasks.first?.plannedOn, plannedDay)
    }

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

    func testDuplicateProjectIdentitiesHaveOneDeterministicCatalogEntryAcrossLaunchAndCache() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let projectID = UUID()
        let alpha = Project(id: projectID, name: "Alpha", creationOrder: 0)
        let duplicate = Project(id: projectID, name: "Zebra", creationOrder: 0)
        let house = Project(id: UUID(), name: "House", creationOrder: 1)
        container.mainContext.insert(ProjectRecord(project: duplicate))
        container.mainContext.insert(ProjectRecord(project: house))
        container.mainContext.insert(ProjectRecord(project: alpha))
        try container.mainContext.save()
        let transport = ControllableTaskTransport()
        let suite = "ProjectsDuplicateCatalog.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container, sync: .publish(to: transport))
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container, taskList: phone)
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", sync: .mirror(from: transport))
        XCTAssertEqual(projects.projects, [alpha, house])
        XCTAssertEqual(phone.projectCatalog, [alpha, house])
        XCTAssertEqual(watch.projectCatalog, [alpha, house])
        let task = try XCTUnwrap(projects.addTaskForToday(text: "Widgets", to: projectID))
        let snapshot = try XCTUnwrap(transport.published.last)
        transport.deliver(TaskListSnapshot(revision: snapshot.revision + 1, tasks: snapshot.tasks,
                                          projects: [house, duplicate, alpha]))
        XCTAssertEqual(watch.projectCatalog, [alpha, house])
        XCTAssertEqual(watch.tasks.map(\.id), [task.id])
        let disconnected = ControllableTaskTransport()
        disconnected.disconnect()
        let reopened = TaskListStore(userDefaults: defaults, storageKey: "watch", sync: .mirror(from: disconnected))
        XCTAssertEqual(reopened.projectCatalog, [alpha, house])
        XCTAssertEqual(reopened.tasks, watch.tasks)
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
