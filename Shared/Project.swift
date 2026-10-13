import Combine
import Foundation
import SwiftData

struct Project: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let creationOrder: Int64
}

@Model
final class ProjectRecord {
    var id: UUID = UUID()
    var name: String = ""
    var creationOrder: Int64 = 0

    init(project: Project) {
        id = project.id
        name = project.name
        creationOrder = project.creationOrder
    }

    var project: Project { Project(id: id, name: name, creationOrder: creationOrder) }
}

@MainActor
protocol ProjectListBehavior: AnyObject {
    var projects: [Project] { get }
    func memos(in projectID: UUID) -> [Memo]
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

    func unscheduledTasks(in projectID: UUID) -> [DailyTask] {
        taskList.tasks(in: projectID).filter { $0.isUnscheduled && !$0.isComplete }
    }

    @discardableResult
    func addTask(text: String, to projectID: UUID) -> DailyTask? {
        guard projects.contains(where: { $0.id == projectID }) else { return nil }
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
        return project
    }

    @discardableResult
    func renameProject(id: UUID, name: String) -> Project? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let record = records().first(where: { $0.id == id }) else { return nil }
        record.name = name
        try? context.save()
        reload()
        return projects.first { $0.id == id }
    }

    private func records() -> [ProjectRecord] {
        ((try? context.fetch(FetchDescriptor<ProjectRecord>())) ?? []).sorted {
            if $0.creationOrder != $1.creationOrder { return $0.creationOrder < $1.creationOrder }
            if $0.id != $1.id { return $0.id.uuidString < $1.id.uuidString }
            return $0.name < $1.name
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
