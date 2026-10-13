import Combine
import Foundation
import SwiftData

struct Project: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let creationOrder: Int64
    let isArchived: Bool

    init(id: UUID, name: String, creationOrder: Int64, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.creationOrder = creationOrder
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey { case id, name, creationOrder, isArchived }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        creationOrder = try values.decode(Int64.self, forKey: .creationOrder)
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    static func precedes(_ lhs: Project, _ rhs: Project) -> Bool {
        if lhs.creationOrder != rhs.creationOrder { return lhs.creationOrder < rhs.creationOrder }
        if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.isArchived && !rhs.isArchived
    }

    static func orderedUnique(_ projects: [Project]) -> [Project] {
        var seen: Set<UUID> = []
        return projects.sorted(by: precedes).filter { seen.insert($0.id).inserted }
    }
}

@Model
final class ProjectRecord {
    var id: UUID = UUID()
    var name: String = ""
    var creationOrder: Int64 = 0
    var isArchived: Bool = false

    init(project: Project) {
        id = project.id
        name = project.name
        creationOrder = project.creationOrder
        isArchived = project.isArchived
    }

    var project: Project { Project(id: id, name: name, creationOrder: creationOrder, isArchived: isArchived) }
}

@MainActor
protocol ProjectListBehavior: AnyObject {
    var projects: [Project] { get }
    var activeProjects: [Project] { get }
    var archivedProjects: [Project] { get }
    @discardableResult func archiveProject(id: UUID) -> Project?
    @discardableResult func restoreProject(id: UUID) -> Project?
    func memos(in projectID: UUID) -> [Memo]
    var todayProjects: [Project] { get }
    func todayTasks(in projectID: UUID) -> [DailyTask]
    func completedTasks(in projectID: UUID) -> [DailyTask]
    @discardableResult func addTaskForToday(text: String, to projectID: UUID) -> DailyTask?
    @discardableResult func doToday(taskID: UUID) -> DailyTask?
    @discardableResult func returnToProject(taskID: UUID) -> DailyTask?
    func laterTasks(in projectID: UUID) -> [DailyTask]
    @discardableResult func addTask(text: String, to projectID: UUID, plannedFor date: Date) -> DailyTask?
    func unscheduledTasks(in projectID: UUID) -> [DailyTask]
    @discardableResult func addTask(text: String, to projectID: UUID) -> DailyTask?
    @discardableResult func createProject(name: String) -> Project?
    @discardableResult func renameProject(id: UUID, name: String) -> Project?
}

@MainActor
final class ProjectListStore: ObservableObject, ProjectListBehavior {
    @Published private(set) var projects: [Project] = []
    let taskList: TaskListStore
    let memoStore: MemoStore?
    private let context: ModelContext

    init(modelContainer: ModelContainer, taskList: TaskListStore, memoStore: MemoStore? = nil) {
        context = modelContainer.mainContext
        self.taskList = taskList
        self.memoStore = memoStore
        reload()
    }

    func memos(in projectID: UUID) -> [Memo] {
        memoStore?.memos(in: projectID) ?? []
    }

    var activeProjects: [Project] { projects.filter { !$0.isArchived } }
    var archivedProjects: [Project] { projects.filter(\.isArchived) }

    @discardableResult
    func archiveProject(id: UUID) -> Project? { setArchived(id: id, isArchived: true) }

    @discardableResult
    func restoreProject(id: UUID) -> Project? { setArchived(id: id, isArchived: false) }

    private func setArchived(id: UUID, isArchived: Bool) -> Project? {
        guard let record = records().first(where: { $0.id == id }) else { return nil }
        record.isArchived = isArchived
        try? context.save()
        reload()
        taskList.refreshProjectCatalog()
        return projects.first { $0.id == id }
    }

    var todayProjects: [Project] {
        activeProjects.filter { !todayTasks(in: $0.id).isEmpty }
    }

    func todayTasks(in projectID: UUID) -> [DailyTask] {
        taskList.referenceTodayTasks(in: projectID)
    }

    func completedTasks(in projectID: UUID) -> [DailyTask] {
        taskList.tasks(in: projectID).filter(\.isComplete)
    }

    @discardableResult
    func addTaskForToday(text: String, to projectID: UUID) -> DailyTask? {
        guard let task = addTask(text: text, to: projectID) else { return nil }
        return doToday(taskID: task.id)
    }

    @discardableResult
    func doToday(taskID: UUID) -> DailyTask? {
        guard activeProjects.contains(where: { project in taskList.tasks(in: project.id).contains { $0.id == taskID } }) else { return nil }
        return taskList.bringTaskToToday(id: taskID)
    }

    @discardableResult
    func returnToProject(taskID: UUID) -> DailyTask? {
        guard activeProjects.contains(where: { project in taskList.tasks(in: project.id).contains { $0.id == taskID } }) else { return nil }
        return taskList.returnTaskToProject(id: taskID)
    }

    func laterTasks(in projectID: UUID) -> [DailyTask] {
        taskList.referenceLaterTasks(in: projectID)
    }

    @discardableResult
    func addTask(text: String, to projectID: UUID, plannedFor date: Date) -> DailyTask? {
        guard activeProjects.contains(where: { $0.id == projectID }) else { return nil }
        return taskList.addTask(text: text, projectID: projectID, plannedFor: date)
    }

    func unscheduledTasks(in projectID: UUID) -> [DailyTask] {
        taskList.tasks(in: projectID).filter { $0.isUnscheduled && !$0.isComplete }
    }

    @discardableResult
    func addTask(text: String, to projectID: UUID) -> DailyTask? {
        guard activeProjects.contains(where: { $0.id == projectID }) else { return nil }
        return taskList.addUnscheduledTask(text: text, projectID: projectID)
    }

    @discardableResult
    func createProject(name: String) -> Project? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let project = Project(id: UUID(), name: name, creationOrder: (projects.map(\.creationOrder).max() ?? -1) + 1)
        context.insert(ProjectRecord(project: project))
        try? context.save()
        reload()
        taskList.refreshProjectCatalog()
        return project
    }

    @discardableResult
    func renameProject(id: UUID, name: String) -> Project? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let record = records().first(where: { $0.id == id }), !record.isArchived else { return nil }
        record.name = name
        try? context.save()
        reload()
        taskList.refreshProjectCatalog()
        return projects.first { $0.id == id }
    }

    private func records() -> [ProjectRecord] {
        ((try? context.fetch(FetchDescriptor<ProjectRecord>())) ?? []).sorted {
            Project.precedes($0.project, $1.project)
        }
    }

    private func reload() {
        var seen: Set<UUID> = []
        let records = records()
        for record in records where !seen.insert(record.id).inserted { context.delete(record) }
        if context.hasChanges { try? context.save() }
        projects = self.records().map(\.project)
    }
}
