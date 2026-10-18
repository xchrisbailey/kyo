import SwiftUI

struct LaterSheet: View {
    @Environment(\.projectsEnabled) private var projectsEnabled
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var taskList: TaskListStore
    var languageModel: any OnDeviceLanguageModel = FoundationOnDeviceLanguageModel()
    @State private var editingTask: DailyTask?
    @State private var reschedulingTask: DailyTask?

    var body: some View {
        NavigationStack {
            List {
                if taskList.laterTasks.isEmpty {
                    ThemedListGroup {
                        Text("No deferred tasks")
                            .accessibilityIdentifier("later-empty")
                    }
                }
                ForEach(taskList.laterTasks) { task in
                    ThemedListGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.text)
                                .accessibilityIdentifier("later-task-\(task.id.uuidString)")
                            if projectsEnabled, let project = taskList.projectCatalog.first(where: { $0.id == task.projectID }) {
                                Text(project.name)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.secondaryText)
                                    .accessibilityIdentifier("later-task-project-\(task.id.uuidString)")
                            }
                            if let date = task.plannedOn?.date(in: .autoupdatingCurrent) {
                                Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                                    .font(.subheadline)
                                    .foregroundStyle(theme.secondaryText)
                                    .accessibilityIdentifier("later-task-planned-day-\(task.id.uuidString)")
                            }
                            TaskProjectAssignmentMenu(task: task, projects: taskList.projectCatalog) {
                                taskList.assignTask(id: task.id, to: $0)
                            }
                            Button("Edit") { editingTask = task }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("later-task-edit-\(task.id.uuidString)")
                            Button("Reschedule") { reschedulingTask = task }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("later-task-reschedule-\(task.id.uuidString)")
                            Button("Bring to Today") { taskList.bringTaskToToday(id: task.id) }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("task-bring-to-today-\(task.id.uuidString)")
                            if projectsEnabled && task.projectID != nil {
                                Button("Return to project") { taskList.returnTaskToProject(id: task.id) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("later-task-return-to-project-\(task.id.uuidString)")
                            }
                            Button("Delete", role: .destructive) { taskList.deleteTask(id: task.id) }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("later-task-delete-\(task.id.uuidString)")
                        }
                    }
                }
            }
            .sheet(item: $editingTask) { task in
                LaterTaskEditSheet(task: task) { text in
                    taskList.editTask(id: task.id, text: text) != nil
                }
            }
            .sheet(item: $reschedulingTask) { task in
                TaskSchedulingSheet(date: task.plannedOn?.date(in: .autoupdatingCurrent), languageModel: languageModel) { date in
                    taskList.deferTask(id: task.id, to: date) != nil
                }
            }
            .themedListBackground()
            .themedNavigationTitle("Later")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("later-done")
                }
            }
        }
    }
}

private struct LaterTaskEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let onSave: (String) -> Bool

    init(task: DailyTask, onSave: @escaping (String) -> Bool) {
        _text = State(initialValue: task.text)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $text)
                    .accessibilityIdentifier("later-task-editor")
            }
            .navigationTitle("Edit task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("later-edit-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(text) { dismiss() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("later-edit-save")
                }
            }
        }
    }
}
