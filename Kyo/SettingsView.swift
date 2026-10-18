import SwiftUI

/// App appearance, optional Projects organization, and Schedule preferences.
struct SettingsSheet: View {
    @ObservedObject var schedule: ScheduleStore
    @ObservedObject var themes: ThemeStore
    @ObservedObject var palette: PalettePreferenceStore
    @ObservedObject var projectsPreference: ProjectsPreferenceStore
    var onOpenProjects: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ThemedListGroup("Appearance") {
                    ThemePicker(store: themes)
                    PalettePicker(store: palette)
                }

                ThemedListGroup("Projects") {
                    Toggle("Use Projects", isOn: Binding(
                        get: { projectsPreference.isEnabled },
                        set: { projectsPreference.setEnabled($0) }
                    ))
                    .accessibilityIdentifier("settings-projects-enabled")
                    if projectsPreference.isEnabled {
                        Button("All projects", action: onOpenProjects)
                            .accessibilityIdentifier("settings-all-projects")
                    }
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
