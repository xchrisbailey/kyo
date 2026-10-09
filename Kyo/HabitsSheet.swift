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

    @Environment(\.theme) private var theme
    @ObservedObject var habitList: HabitListStore
    @Environment(\.dismiss) private var dismiss
    @State private var editMode = EditMode.inactive
    @State private var pendingDelete: Habit?

    var body: some View {
        List {
            ForEach(habitList.habitOverviews) { overview in
                NavigationLink {
                    HabitForm(
                        habit: overview.habit,
                        onSave: { name, schedule in habitList.editHabit(id: overview.id, name: name, schedule: schedule) != nil },
                        onDelete: { habitList.deleteHabit(id: overview.id) }
                    )
                } label: {
                    HabitsSheetRow(overview: overview)
                }
                .accessibilityHint("Edits this habit")
                .listRowBackground(theme.listRow)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { pendingDelete = overview.habit }
                        .accessibilityLabel("Delete habit: \(overview.habit.name)")
                }
            }
            .onMove { habitList.moveHabits(fromOffsets: $0, toOffset: $1) }
        }
        .themedListBackground()
        .overlay {
            if habitList.habitOverviews.isEmpty {
                Text("No habits yet")
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .themedNavigationTitle("Habits")
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

    @Environment(\.theme) private var theme
    let overview: HabitOverview

    var body: some View {
        let summary = overview.habit.schedule.summary(calendar: .current)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(overview.habit.name)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(summary)
                    if !overview.isOnToday {
                        Text("·")
                        Text("Not today")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 8)
            HabitStatusLabel(weekProgress: overview.weekProgress, streak: overview.streak)
                .foregroundStyle(theme.primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overview.habit.name)
        .accessibilityValue(accessibilityValue(summary: summary))
        .accessibilityIdentifier("habit-row-\(overview.id.uuidString)")
    }

    /// The schedule summary, "not due today" where it applies, then week progress and the streak.
    private func accessibilityValue(summary: String) -> String {
        var parts = [summary]
        if !overview.isOnToday { parts.append("not due today") }
        if let progress = overview.weekProgress { parts.append(HabitStatusLabel.spokenWeekProgress(progress)) }
        if overview.streak >= 1 {
            parts.append(HabitStatusLabel.spokenStreak(overview.streak, isWeekly: overview.weekProgress != nil))
        }
        return parts.joined(separator: ", ")
    }
}
