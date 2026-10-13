import SwiftUI

struct ProjectsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var projects: ProjectListStore
    @State private var isCreating = false

    init(projects: ProjectListStore, startCreating: Bool = false) {
        self.projects = projects
        _isCreating = State(initialValue: startCreating)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(projects.projects) { project in
                    NavigationLink {
                        ProjectDetailView(projectID: project.id, projects: projects, taskList: projects.taskList, onDone: { dismiss() })
                    } label: {
                        Text(project.name)
                    }
                    .accessibilityIdentifier("project-open-\(project.id.uuidString)")
                }
                Button("New project") { isCreating = true }
                    .accessibilityIdentifier("project-new")
            }
            .navigationTitle("All projects")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("projects-done")
                }
            }
            .sheet(isPresented: $isCreating) {
                ProjectTextForm(title: "New project", field: "Project name", identifier: "project-name") {
                    projects.createProject(name: $0) != nil
                }
            }
        }
    }
}

private struct ProjectDetailView: View {
    let projectID: UUID
    @ObservedObject var projects: ProjectListStore
    @ObservedObject var taskList: TaskListStore
    let onDone: () -> Void
    @State private var isRenaming = false
    @State private var isAddingTask = false
    @State private var editingTask: DailyTask?
    @State private var shareItems: ShareItems?

    private var name: String { projects.projects.first { $0.id == projectID }?.name ?? "Project" }

    var body: some View {
        List {
            Section("Unscheduled") {
                ForEach(projects.unscheduledTasks(in: projectID)) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.text)
                            .accessibilityIdentifier("project-task-text-\(task.id.uuidString)")
                        HStack {
                            Button("Edit") { editingTask = task }
                                .accessibilityIdentifier("project-task-edit-\(task.id.uuidString)")
                            Button("Share") { shareItems = ShareItems(.make(for: task)) }
                                .accessibilityIdentifier("project-task-share-\(task.id.uuidString)")
                            Button("Delete", role: .destructive) { taskList.deleteTask(id: task.id) }
                                .accessibilityIdentifier("project-task-delete-\(task.id.uuidString)")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add task") { isAddingTask = true }
                    .accessibilityIdentifier("project-add-task")
            }
        }
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .accessibilityIdentifier("projects-done")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Rename") { isRenaming = true }
                    .accessibilityIdentifier("project-rename")
            }
        }
        .sheet(isPresented: $isRenaming) {
            ProjectTextForm(title: "Rename project", field: "Project name", identifier: "project-name", text: name) {
                projects.renameProject(id: projectID, name: $0) != nil
            }
        }
        .sheet(isPresented: $isAddingTask) {
            ProjectTextForm(title: "Add task", field: "Task", identifier: "project-task") {
                projects.addTask(text: $0, to: projectID) != nil
            }
        }
        .sheet(item: $editingTask) { task in
            ProjectTextForm(title: "Edit task", field: "Task", identifier: "project-task", text: task.text) {
                taskList.editTask(id: task.id, text: $0) != nil
            }
        }
        .popover(item: $shareItems) { items in
            ShareSheet(items: items) { shareItems = nil }
                .presentationDetents([.medium, .large])
                .presentationCompactAdaptation(.sheet)
        }
    }
}

private struct ProjectTextForm: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let field: String
    let identifier: String
    @State var text: String = ""
    let onSave: (String) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(field, text: $text)
                    .accessibilityIdentifier("\(identifier)-editor")
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("\(identifier)-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if onSave(text) { dismiss() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("\(identifier)-save")
                }
            }
        }
    }
}
