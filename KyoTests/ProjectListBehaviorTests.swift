import SwiftData
import XCTest

@MainActor
final class ProjectListBehaviorTests: XCTestCase {
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
}
