import SwiftUI

/// The Settings sheet: the Appearance and Schedule groups.
struct SettingsSheet: View {
    @ObservedObject var schedule: ScheduleStore
    @ObservedObject var themes: ThemeStore
    @ObservedObject var palette: PalettePreferenceStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ThemedListGroup("Appearance") {
                    ThemePicker(store: themes)
                    PalettePicker(store: palette)
                }

                ThemedListGroup("Schedule") {
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
            .themedListBackground()
            .themedNavigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings-done")
                }
            }
        }
    }
}
