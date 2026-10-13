import SwiftUI

struct ProjectsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var projects: ProjectListStore
    @ObservedObject var sections: CollapsedSections
    @State private var isCreating = false

    init(projects: ProjectListStore, sections: CollapsedSections, startCreating: Bool = false) {
        self.projects = projects
        self.sections = sections
        _isCreating = State(initialValue: startCreating)
    }

    var body: some View {
        NavigationStack {
            List {
                ThemedListGroup {
                    ForEach(projects.projects) { project in
                        NavigationLink {
                            ProjectDetailView(projectID: project.id, projects: projects, taskList: projects.taskList, sections: sections, onDone: { dismiss() })
                        } label: {
                            Text(project.name)
                        }
                        .accessibilityIdentifier("project-open-\(project.id.uuidString)")
                    }
                    Button("New project") { isCreating = true }
                        .accessibilityIdentifier("project-new")
                }
            }
            .themedListBackground()
            .themedNavigationTitle("All projects")
            .navigationBarTitleDisplayMode(.inline)
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

struct ProjectDetailView: View {
    @Environment(\.theme) private var theme
    let projectID: UUID
    @ObservedObject var projects: ProjectListStore
    @ObservedObject var taskList: TaskListStore
    @ObservedObject var sections: CollapsedSections
    let onDone: () -> Void
    @State private var isRenaming = false
    @State private var isAddingTask = false
    @State private var schedulingTask: DailyTask?

    private var name: String { projects.projects.first { $0.id == projectID }?.name ?? "Project" }

    var body: some View {
        List {
            ThemedListGroup("Today") {
                ForEach(projects.todayTasks(in: projectID).filter { !$0.isComplete }) { task in
                    taskRow(task)
                }
            }
            ThemedListGroup("Later") {
                ForEach(projects.laterTasks(in: projectID)) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        taskRow(task)
                        if let date = task.plannedOn?.date(in: .autoupdatingCurrent) {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                                .padding(.horizontal, 14)
                                .accessibilityIdentifier("project-task-planned-day-\(task.id.uuidString)")
                        }
                    }
                }
            }
            ThemedListGroup("Unscheduled") {
                ForEach(projects.unscheduledTasks(in: projectID)) { task in
                    taskRow(task)
                }
                Button("Add task") { isAddingTask = true }
                    .accessibilityIdentifier("project-add-task")
            }
            ThemedListGroup {
                Button {
                    sections.toggleCompleted(projectID)
                } label: {
                    Label("Completed", systemImage: sections.isCompletedCollapsed(projectID) ? "chevron.right" : "chevron.down")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityValue(sections.isCompletedCollapsed(projectID) ? "collapsed" : "expanded")
                .accessibilityIdentifier("project-completed-collapse-\(projectID.uuidString)")
                if !sections.isCompletedCollapsed(projectID) {
                    ForEach(projects.completedTasks(in: projectID)) { task in
                        taskRow(task)
                    }
                }
            }
        }
        .themedListBackground()
        .themedNavigationTitle(LocalizedStringKey(name))
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(item: $schedulingTask) { task in
            TaskSchedulingSheet(date: task.plannedOn?.date(in: .autoupdatingCurrent)) {
                taskList.deferTask(id: task.id, to: $0) != nil
            }
        }
        .sheet(isPresented: $isAddingTask) {
            ProjectTextForm(title: "Add task", field: "Task", identifier: "project-task") {
                projects.addTask(text: $0, to: projectID) != nil
            }
        }
    }

    private func taskRow(_ task: DailyTask) -> some View {
        TaskRow(task: task,
                onToggle: {
                    if task.isUnscheduled && !task.isComplete { projects.doToday(taskID: task.id) }
                    else { taskList.toggleTask(id: task.id) }
                },
                onEdit: { taskList.editTask(id: task.id, text: $0) != nil },
                onDelete: { taskList.deleteTask(id: task.id) },
                onDoLater: { schedulingTask = task },
                onReturnToProject: task.isUnscheduled ? nil : { projects.returnToProject(taskID: task.id) })
            .listRowInsets(EdgeInsets())
    }
}

struct ProjectTextForm: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let field: String
    let identifier: String
    @State var text: String = ""
    let onSave: (String) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                ThemedListGroup {
                    TextField(field, text: $text)
                        .accessibilityIdentifier("\(identifier)-editor")
                }
            }
            .themedListBackground()
            .themedNavigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
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
