import SwiftUI

/// The Schedule section's card content: a prompt line while Kyo can't read the calendars (Connect,
/// access off, access unavailable), and Today's events once access is granted.
struct ScheduleSectionContent: View {
    @ObservedObject var schedule: ScheduleStore

    var body: some View {
        VStack(spacing: 0) {
            if schedule.showsConnectPrompt {
                promptLine(
                    "See today's events", button: "Connect", buttonID: "schedule-connect",
                    action: { Task { await schedule.connect() } }
                )
            } else if schedule.showsAccessOffLine {
                promptLine(
                    "Calendar access is off", button: "Open Settings", buttonID: "schedule-open-settings",
                    buttonValue: schedule.reportsSettingsRequests && schedule.settingsOpenRequests > 0 ? "Requested" : nil,
                    action: { schedule.openSettings() }
                )
            } else if schedule.showsUnavailableLine {
                promptLine("Calendar access isn't available")
            } else if schedule.showsNothingScheduled {
                Text("Nothing scheduled")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                    .padding(.horizontal, 14)
            } else if schedule.showsEvents {
                if let line = schedule.allDayLine, let label = schedule.allDayAccessibilityLabel {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 14)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label)
                        .accessibilityIdentifier("schedule-all-day")
                    if !schedule.timedEvents.isEmpty { divider }
                }
                ForEach(Array(schedule.timedEvents.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { divider }
                    ScheduleRow(
                        event: event,
                        timeText: schedule.timeText(for: event),
                        accessibilityLabel: schedule.accessibilityLabel(for: event)
                    )
                }
            }
        }
    }

    /// A muted line with an optional button and the dismiss control, which turns Show schedule off.
    private func promptLine(
        _ text: String, button: String? = nil, buttonID: String = "", buttonValue: String? = nil,
        action: @escaping () -> Void = {}
    ) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let button {
                Button(action: action) {
                    Text(button)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KyoPalette.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(buttonValue ?? "")
                .accessibilityIdentifier(buttonID)
            }
            Button {
                schedule.dismissSchedule()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide schedule")
            .accessibilityHint("Turns off Show schedule in Settings")
            .accessibilityIdentifier("schedule-dismiss")
        }
        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.55))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

private struct ScheduleRow: View {
    let event: ScheduleEvent
    let timeText: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(.sRGB, red: event.calendarColor.red, green: event.calendarColor.green, blue: event.calendarColor.blue, opacity: event.calendarColor.alpha))
                .frame(width: 9, height: 9)
            Text(timeText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Text(event.displayTitle)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
