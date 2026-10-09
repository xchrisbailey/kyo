import SwiftUI

/// Settings → Schedule → Calendars: the device's calendars grouped by account, each with its colour
/// and a checkmark while its events are shown. Without full access it shows Today's access line.
struct ScheduleCalendarsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var schedule: ScheduleStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if schedule.showsEvents {
                if schedule.calendarGroups.isEmpty {
                    Text("No calendars")
                        .foregroundStyle(theme.secondaryText)
                        .listRowBackground(theme.listRow)
                }
                ForEach(schedule.calendarGroups) { group in
                    Section(group.accountTitle) {
                        ForEach(group.calendars) { calendar in
                            ScheduleCalendarRow(calendar: calendar, isVisible: schedule.isCalendarVisible(calendar.id)) {
                                schedule.toggleCalendar(calendar.id)
                            }
                        }
                    }
                    .listRowBackground(theme.listRow)
                }
            } else if schedule.showsSection {
                Section {
                    ScheduleSectionContent(schedule: schedule)
                        .listRowInsets(EdgeInsets())
                }
                .listRowBackground(theme.listRow)
            }
        }
        .themedListBackground()
        .themedNavigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        // Hiding the schedule from the access line leaves nothing to choose.
        .onChange(of: schedule.showsSchedule) { _, shows in
            if !shows { dismiss() }
        }
    }
}

private struct ScheduleCalendarRow: View {

    @Environment(\.theme) private var theme
    let calendar: ScheduleCalendar
    let isVisible: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(.sRGB, red: calendar.color.red, green: calendar.color.green, blue: calendar.color.blue, opacity: calendar.color.alpha))
                    .frame(width: 12, height: 12)
                Text(calendar.title)
                    .foregroundStyle(theme.primaryText)
                Spacer(minLength: 8)
                if isVisible {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calendar.title)
        .accessibilityValue(isVisible ? "Shown" : "Hidden")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("schedule-calendar-\(calendar.id)")
    }
}
