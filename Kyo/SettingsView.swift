import SwiftUI

/// The Settings sheet: the Schedule group.
struct SettingsSheet: View {
    @ObservedObject var schedule: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
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
                .listRowBackground(theme.listRow)
            }
            .listStyle(.insetGrouped)
            .themedListBackground()
            .themedNavigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
