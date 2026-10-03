import SwiftUI

/// The Settings sheet: grouped entries. Habits, then the Schedule group.
struct SettingsSheet: View {
    @ObservedObject var habitList: HabitListStore
    @ObservedObject var schedule: ScheduleStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HabitManagerView(habitList: habitList)
                    } label: {
                        Text("Habits")
                    }
                    .accessibilityHint("Add, edit, reorder and delete habits")
                }
                Section("Schedule") {
                    Toggle("Show schedule", isOn: Binding(
                        get: { schedule.showsSchedule },
                        set: { schedule.setShowsSchedule($0) }
                    ))
                    .accessibilityHint("Shows today's calendar events on Today")
                    NavigationLink {
                        ScheduleCalendarsView(schedule: schedule)
                    } label: {
                        Text("Calendars")
                    }
                    .disabled(!schedule.showsSchedule)
                    .accessibilityHint("Chooses which calendars the schedule shows")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Every habit in manager order, with add, edit, swipe-to-delete and drag-to-reorder.
struct HabitManagerView: View {
    @ObservedObject var habitList: HabitListStore
    @State private var pendingDelete: Habit?

    var body: some View {
        List {
            ForEach(habitList.habits) { habit in
                NavigationLink {
                    HabitForm(
                        habit: habit,
                        onSave: { name, schedule in habitList.editHabit(id: habit.id, name: name, schedule: schedule) != nil },
                        onDelete: { habitList.deleteHabit(id: habit.id) }
                    )
                } label: {
                    HabitManagerRow(habit: habit)
                }
                .accessibilityHint("Edits this habit")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { pendingDelete = habit }
                        .accessibilityLabel("Delete habit: \(habit.name)")
                }
            }
            .onMove { habitList.moveHabits(fromOffsets: $0, toOffset: $1) }
        }
        .overlay {
            if habitList.habits.isEmpty {
                Text("No habits yet")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Habits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
    }
}

private struct HabitManagerRow: View {
    let habit: Habit

    var body: some View {
        let calendar = Calendar.current
        let isDueToday = habit.isDue(on: .now, calendar: calendar)
        let summary = habit.schedule.summary(calendar: calendar)
        VStack(alignment: .leading, spacing: 2) {
            Text(habit.name)
                .font(.body)
            HStack(spacing: 6) {
                Text(summary)
                if !isDueToday {
                    Text("·")
                    Text("Not today")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.name)
        .accessibilityValue(isDueToday ? summary : "\(summary), not due today")
    }
}
