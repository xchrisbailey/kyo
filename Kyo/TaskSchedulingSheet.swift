import SwiftUI

struct TaskSchedulingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var workflow: TaskSchedulingWorkflow
    @State private var interpretationTask: Task<Void, Never>?
    @FocusState private var isDescriptionFocused: Bool
    let onConfirm: (Date) -> Bool

    init(date: Date? = nil, languageModel: any OnDeviceLanguageModel = FoundationOnDeviceLanguageModel(), onConfirm: @escaping (Date) -> Bool) {
        _workflow = StateObject(wrappedValue: TaskSchedulingWorkflow(date: date, languageModel: languageModel))
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick choices") {
                    Menu("Weekday") {
                        ForEach(0..<7, id: \.self) { offset in
                            let weekday = (workflow.calendar.firstWeekday - 1 + offset) % 7 + 1
                            Button(workflow.calendar.weekdaySymbols[weekday - 1]) {
                                workflow.choose(.weekday(weekday))
                            }
                            .accessibilityIdentifier("task-scheduling-weekday-\(weekday)")
                        }
                    }
                    .accessibilityIdentifier("task-scheduling-weekday")
                    Button("One week out") { workflow.choose(.weeks(1)) }
                        .accessibilityIdentifier("task-scheduling-one-week")
                    Button("One month out") { workflow.choose(.months(1)) }
                        .accessibilityIdentifier("task-scheduling-one-month")
                }
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
                Section("Describe a planned day") {
                    TextField("For example, next Friday", text: $workflow.schedulingDescription, axis: .vertical)
                        .focused($isDescriptionFocused)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("task-scheduling-description")
                    if let unavailable = workflow.availabilityMessage {
                        Text(unavailable)
                            .font(.footnote)
                            .accessibilityIdentifier("task-scheduling-unavailable")
                    }
                    Button("Interpret") {
                        isDescriptionFocused = false
                        interpretationTask?.cancel()
                        interpretationTask = Task { await workflow.interpretDescription() }
                    }
                    .disabled(workflow.isInterpreting || workflow.availabilityMessage != nil ||
                              workflow.schedulingDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("task-scheduling-interpret")
                    if workflow.isInterpreting {
                        ProgressView("Interpreting…")
                            .accessibilityIdentifier("task-scheduling-interpreting")
                    }
                }
                if let message = workflow.message {
                    Section {
                        Text(message)
                            .accessibilityIdentifier("task-scheduling-message")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Do later")
            .onDisappear {
                interpretationTask?.cancel()
                workflow.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        interpretationTask?.cancel()
                        workflow.cancel()
                        dismiss()
                    }
                        .accessibilityIdentifier("task-scheduling-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        if workflow.confirm(onConfirm) { dismiss() }
                    }
                    .disabled(!workflow.canConfirm)
                    .accessibilityIdentifier("task-scheduling-confirm")
                }
            }
        }
    }
}
