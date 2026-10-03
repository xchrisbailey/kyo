import SwiftUI

/// The Schedule section's card content: the Connect line while access is undecided, then Today's
/// events once it's granted. The other authorization states render nothing yet.
struct ScheduleSectionContent: View {
    @ObservedObject var schedule: ScheduleStore

    var body: some View {
        VStack(spacing: 0) {
            if schedule.showsConnectPrompt {
                connectLine
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

    private var connectLine: some View {
        HStack(spacing: 12) {
            Text("See today's events")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                Task { await schedule.connect() }
            } label: {
                Text("Connect")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(KyoPalette.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("schedule-connect")
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
