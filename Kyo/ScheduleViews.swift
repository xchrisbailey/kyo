import SwiftUI

/// The Schedule section's card content: a prompt line while Kyo can't read the calendars (Connect,
/// access off, access unavailable), and Today's events once access is granted, compact until the user shows more.
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
                    Button {
                        schedule.openAllDayEvents()
                    } label: {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows event details")
                    .accessibilityIdentifier("schedule-all-day")
                    if !schedule.timedEvents.isEmpty { divider }
                }
                if schedule.showsNothingElseToday {
                    Text("Nothing else today")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                        .padding(.horizontal, 14)
                        .accessibilityIdentifier("schedule-nothing-else")
                }
                ForEach(Array(schedule.visibleRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { divider }
                    ScheduleRow(row: row, open: { schedule.open(row.event.id) })
                }
                if let more = schedule.moreText, let label = schedule.moreAccessibilityLabel {
                    divider
                    toggleLine(more, accessibilityLabel: label, identifier: "schedule-more") {
                        schedule.showMore()
                    }
                } else if schedule.showsShowLess {
                    divider
                    toggleLine("Show less", accessibilityLabel: "Show less", identifier: "schedule-show-less") {
                        schedule.showLess()
                    }
                }
            }
        }
        .animation(.default, value: schedule.isShowingMore)
        // The details of a timed row or a lone all-day event. Opened from the all-day list, they
        // show on top of that list instead.
        .sheet(item: Binding(
            get: { schedule.isChoosingAllDayEvent ? nil : schedule.presentedDetail },
            set: { if $0 == nil { schedule.dismissDetail() } }
        )) { detail in
            EventDetailSheet(detail: detail)
        }
        .sheet(isPresented: Binding(
            get: { schedule.isChoosingAllDayEvent },
            set: { if !$0 { schedule.dismissAllDayChooser() } }
        )) {
            AllDayEventChooser(schedule: schedule)
        }
    }

    private func toggleLine(
        _ title: String, accessibilityLabel: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KyoPalette.accent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
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
    let row: ScheduleRowPresentation
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The width the title and location column is given, and the width the location needs on one line.
    @State private var textWidth: CGFloat = 0
    @State private var locationWidth: CGFloat = .infinity

    private var isPast: Bool { row.state == .past }
    private var color: ScheduleColor { row.event.calendarColor }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color.swiftUIColor)
                    .opacity(isPast ? 0.4 : 1)
                    .frame(width: 9, height: 9)
                timeLabel
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.event.displayTitle)
                        .font(.body)
                        .foregroundStyle(isPast ? .secondary : .primary)
                        .lineLimit(2)
                    if showsLocation, let location = row.location {
                        Text(location)
                            .font(.footnote)
                            .foregroundStyle(isPast ? .tertiary : .secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                .background { locationMeasure }
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows event details")
    }

    /// An invisible copy of the location at its natural one-line width.
    @ViewBuilder
    private var locationMeasure: some View {
        if let location = row.location {
            Text(location)
                .font(.footnote)
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { locationWidth = $0 }
        }
    }

    @ViewBuilder
    private var timeLabel: some View {
        if row.state == .inProgress {
            Text(row.timeText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(KyoPalette.accent)
                .lineLimit(1)
                .fixedSize()
        } else {
            Text(row.timeText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isPast ? .tertiary : .secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// Whether the location is shown: only once measured to fit on one line, and never at
    /// accessibility sizes. Until it's measured it stays out, so a long one can't widen the row.
    private var showsLocation: Bool {
        row.location != nil && !dynamicTypeSize.isAccessibilitySize && locationWidth <= textWidth
    }
}

private extension ScheduleColor {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// Hosts the view controller that shows an event's details, with a Done button of its own.
private struct EventDetailHost: UIViewControllerRepresentable {
    let viewController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController { viewController }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct EventDetailSheet: View {
    let detail: PresentedEventDetail

    var body: some View {
        EventDetailHost(viewController: detail.viewController)
            .ignoresSafeArea()
    }
}

/// The titles of Today's all-day events, to choose which one to open. Its details show on top.
private struct AllDayEventChooser: View {
    @ObservedObject var schedule: ScheduleStore

    var body: some View {
        NavigationStack {
            List(schedule.allDayEvents) { event in
                Button {
                    schedule.open(event.id)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(event.calendarColor.swiftUIColor)
                            .frame(width: 9, height: 9)
                        Text(event.displayTitle)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("\(event.displayTitle), \(event.calendarTitle) calendar")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows event details")
            }
            .navigationTitle("All day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { schedule.dismissAllDayChooser() }
                }
            }
        }
        .presentationDetents([.medium])
        .sheet(item: Binding(
            get: { schedule.presentedDetail },
            set: { if $0 == nil { schedule.dismissDetail() } }
        )) { detail in
            EventDetailSheet(detail: detail)
        }
    }
}
