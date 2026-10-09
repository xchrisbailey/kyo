import SwiftUI

/// The habit form's content, for adding (`habit == nil`) or editing. It has no navigation
/// container of its own, so it works pushed inside a `NavigationStack` (the Habits sheet) or
/// wrapped by `HabitFormSheet`. Saving and deleting dismiss it, which pops it when pushed.
struct HabitForm: View {
    private enum ScheduleKind: String, CaseIterable, Identifiable {
        case everyDay = "Every day"
        case weekdays = "Weekdays"
        case weeklyTarget = "Weekly target"

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var name: String
    @State private var kind: ScheduleKind
    @State private var weekdays: Set<Int>
    @State private var weeklyTarget: Int
    @State private var isConfirmingDelete = false
    @FocusState private var isNameFocused: Bool
    /// The habit being edited; `nil` when adding.
    private let habit: Habit?
    /// Whether to show a Cancel button; a pushed form has the back button instead.
    private let showsCancel: Bool
    /// Returns whether the habit was saved.
    private let onSave: (String, HabitSchedule) -> Bool
    private let onDelete: () -> Void

    init(
        habit: Habit? = nil,
        showsCancel: Bool = false,
        onSave: @escaping (String, HabitSchedule) -> Bool,
        onDelete: @escaping () -> Void = {}
    ) {
        self.habit = habit
        self.showsCancel = showsCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: habit?.name ?? "")
        switch habit?.schedule ?? .everyDay {
        case .everyDay:
            _kind = State(initialValue: .everyDay)
            _weekdays = State(initialValue: [])
            _weeklyTarget = State(initialValue: 3)
        case .weekdays(let days):
            _kind = State(initialValue: .weekdays)
            _weekdays = State(initialValue: days)
            _weeklyTarget = State(initialValue: 3)
        case .weeklyTarget(let target):
            _kind = State(initialValue: .weeklyTarget)
            _weekdays = State(initialValue: [])
            _weeklyTarget = State(initialValue: target)
        }
    }

    private var schedule: HabitSchedule {
        switch kind {
        case .everyDay: .everyDay
        case .weekdays: .weekdays(weekdays)
        case .weeklyTarget: .weeklyTarget(weeklyTarget)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && schedule.isValid
    }

    var body: some View {
        Form {
            ThemedListGroup {
                TextField("Name", text: $name)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityLabel("Habit name")
            }
            ThemedListGroup("Schedule") {
                Picker("Schedule", selection: $kind) {
                    ForEach(ScheduleKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch kind {
                case .everyDay:
                    EmptyView()
                case .weekdays:
                    WeekdayChips(selection: $weekdays)
                case .weeklyTarget:
                    Stepper(
                        weeklyTarget == 1 ? "1 day a week" : "\(weeklyTarget) days a week",
                        value: $weeklyTarget,
                        in: HabitSchedule.weeklyTargetRange
                    )
                }
            }
            if habit != nil {
                ThemedListGroup {
                    Button("Delete habit", role: .destructive) { isConfirmingDelete = true }
                        .foregroundStyle(theme.destructive)
                        .accessibilityHint("Deletes this habit and its log")
                }
            }
        }
        .themedListBackground()
        .themedNavigationTitle(habit == nil ? "New Habit" : "Edit Habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .onAppear { isNameFocused = habit == nil }
        .confirmationDialog("Delete this habit?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete habit and log", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(habit?.name ?? "")\" and its log. It can't be undone.")
        }
    }

    private func save() {
        guard canSave, onSave(name, schedule) else { return }
        dismiss()
    }
}

/// The habit form presented as a sheet, in its own navigation stack.
struct HabitFormSheet: View {
    var habit: Habit?
    let onSave: (String, HabitSchedule) -> Bool
    var onDelete: () -> Void = {}

    var body: some View {
        NavigationStack {
            HabitForm(habit: habit, showsCancel: true, onSave: onSave, onDelete: onDelete)
        }
        .presentationDetents([.medium, .large])
    }
}

/// One toggle chip per weekday, in the device locale's week order.
struct WeekdayChips: View {
    @Binding var selection: Set<Int>
    @Environment(\.theme) private var theme

    var body: some View {
        let calendar = Calendar.current
        HStack(spacing: 6) {
            ForEach(HabitSchedule.weekdaysInWeekOrder(calendar: calendar), id: \.self) { day in
                let isSelected = selection.contains(day)
                Button {
                    if isSelected { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isSelected ? theme.onAccent : theme.primaryText)
                        .background(Circle().fill(isSelected ? theme.accent : theme.fill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[day - 1])
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
