import SwiftUI

struct TaskSchedulingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var workflow: TaskSchedulingWorkflow
    let onConfirm: (Date) -> Bool

    init(date: Date? = nil, onConfirm: @escaping (Date) -> Bool) {
        _workflow = StateObject(wrappedValue: TaskSchedulingWorkflow(date: date))
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Planned day") {
                    DatePicker("Choose a date", selection: $workflow.proposedDate, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .accessibilityIdentifier("task-planned-day-picker")
                    Text(workflow.preview)
                        .accessibilityIdentifier("task-planned-day-preview")
                    Text("This task appears on Today on this day and carries forward until completed.")
                        .font(.footnote)
                    Button("Today", action: workflow.chooseToday)
                        .accessibilityIdentifier("task-scheduling-today")
                }
                if let message = workflow.message {
                    Section {
                        Text(message)
                            .accessibilityIdentifier("task-scheduling-message")
                    }
                }
            }
            .navigationTitle("Do later")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("task-scheduling-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        if workflow.confirm(onConfirm) { dismiss() }
                    }
                    .accessibilityIdentifier("task-scheduling-confirm")
                }
            }
        }
    }
}

struct LaterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var taskList: TaskListStore

    var body: some View {
        NavigationStack {
            List {
                if taskList.laterTasks.isEmpty {
                    Text("No deferred tasks")
                        .accessibilityIdentifier("later-empty")
                }
                ForEach(taskList.laterTasks) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.text)
                            .accessibilityIdentifier("later-task-\(task.id.uuidString)")
                        if let date = task.plannedOn?.date(in: .autoupdatingCurrent) {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Button("Bring to Today") { taskList.bringTaskToToday(id: task.id) }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("task-bring-to-today-\(task.id.uuidString)")
                    }
                }
            }
            .navigationTitle("Later")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("later-done")
                }
            }
        }
    }
}
