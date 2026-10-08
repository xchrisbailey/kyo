import SwiftUI

/// The Habits sheet behind **See all**: every habit in habit order, with add, edit, swipe-to-delete
/// and drag-to-reorder. It has its own navigation stack, so + and tapping a row push the habit form.
struct HabitsSheet: View {
    @ObservedObject var habitList: HabitListStore

    var body: some View {
        NavigationStack {
            HabitsList(habitList: habitList)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct HabitsList: View {
    @ObservedObject var habitList: HabitListStore
    @Environment(\.dismiss) private var dismiss
    @State private var editMode = EditMode.inactive
    @State private var pendingDelete: Habit?

    var body: some View {
        List {
            ForEach(habitList.habitEntries) { entry in
                NavigationLink {
                    HabitForm(
                        habit: entry.habit,
                        onSave: { name, schedule in habitList.editHabit(id: entry.id, name: name, schedule: schedule) != nil },
                        onDelete: { habitList.deleteHabit(id: entry.id) }
                    )
                } label: {
                    HabitsSheetRow(entry: entry)
                }
                .accessibilityHint("Edits this habit")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { pendingDelete = entry.habit }
                        .accessibilityLabel("Delete habit: \(entry.habit.name)")
                }
            }
            .onMove { habitList.moveHabits(fromOffsets: $0, toOffset: $1) }
        }
        .overlay {
            if habitList.habitEntries.isEmpty {
                Text("No habits yet")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Habits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Edit mode's own Done sits in the same corner, so the sheet's Done waits for it to end.
            if !editMode.isEditing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    HabitForm(onSave: { name, schedule in habitList.addHabit(name: name, schedule: schedule) != nil })
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add habit")
                .accessibilityHint("Opens the new habit form")
            }
            ToolbarItem(placement: .primaryAction) {
                EditButton()
                    .accessibilityHint("Lets you drag habits to reorder them")
            }
        }
        .confirmationDialog(
            "Delete this habit?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { habit in
            Button("Delete habit and log", role: .destructive) { habitList.deleteHabit(id: habit.id) }
            Button("Cancel", role: .cancel) {}
        } message: { habit in
            Text("This permanently deletes \"\(habit.name)\" and its log. It can't be undone.")
        }
        // After `.toolbar`, so the Edit button's own state is the one the toolbar reads to hide Done.
        .environment(\.editMode, $editMode)
    }
}

private struct HabitsSheetRow: View {
    let entry: HabitEntry

    var body: some View {
        let summary = entry.habit.schedule.summary(calendar: .current)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.habit.name)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(summary)
                    if !entry.isDueToday {
                        Text("·")
                        Text("Not today")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HabitStatusLabel(weekProgress: entry.weekProgress, streak: entry.streak)
                .foregroundStyle(Color.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.habit.name)
        .accessibilityValue(accessibilityValue(summary: summary))
    }

    /// The schedule summary, "not due today" where it applies, then week progress and the streak.
    private func accessibilityValue(summary: String) -> String {
        var parts = [summary]
        if !entry.isDueToday { parts.append("not due today") }
        if let progress = entry.weekProgress { parts.append("\(progress.count) of \(progress.target) this week") }
        if entry.streak >= 1 {
            parts.append(entry.weekProgress == nil ? "\(entry.streak) day streak" : "\(entry.streak) week streak")
        }
        return parts.joined(separator: ", ")
    }
}
