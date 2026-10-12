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
