import SwiftUI

/// Month: one calendar month as a grid, a legend under it, and the selected day's Day summary.
/// It shows what `MonthModel` reports and changes nothing but the selection.
struct MonthView: View {
    @ObservedObject var model: MonthModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            VStack(spacing: 4) {
                weekdayRow
                ForEach(model.weeks) { week in
                    HStack(spacing: 0) {
                        ForEach(week.cells) { cell in
                            if let day = cell.day {
                                MonthDayCell(day: day) { model.select(day.date) }
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 1)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .padding(8)
            // Seven columns can't hold accessibility-size text, so the grid stops growing at the largest
            // standard size. The header, legend and Day summary keep scaling.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("month-grid")

            legend
                .padding(.top, 12)

            MonthDaySummaryView(summary: model.selectedSummary)
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The month and year, with the chevrons beside them and, away from the current month, the way back.
    /// The controls move below the title when large text leaves them no room beside it.
    private var header: some View {
        let title = Text(model.headerText)
            .font(.largeTitle.weight(.bold))
            .tracking(-1.2)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("month-header")
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    title
                    controls
                }
            } else {
                HStack(spacing: 8) {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    controls
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            if !model.isShowingCurrentMonth {
                MonthControl(systemImage: "arrow.uturn.backward", label: "Back to current month", identifier: "month-jump-back") {
                    model.showCurrentMonth()
                }
            }
            MonthControl(systemImage: "chevron.left", label: "Previous month", identifier: "month-previous") {
                model.showPreviousMonth()
            }
            MonthControl(systemImage: "chevron.right", label: "Next month", identifier: "month-next") {
                model.showNextMonth()
            }
        }
    }

    /// A mostly horizontal drag moves a month. It runs beside the scroll view's own drag, and a mostly
    /// vertical one is left to the scroll view alone.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { drag in
                let across = drag.translation.width
                guard abs(across) > 48, abs(across) > abs(drag.translation.height) * 2 else { return }
                if across < 0 { model.showNextMonth() } else { model.showPreviousMonth() }
            }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.weekdayTitles.enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    /// The four kinds in slot order. It reflows to a column at large text sizes.
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Marks on each day, in order: events, tasks, habits, memos")
        .accessibilityIdentifier("month-legend")
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach(MonthKind.allCases, id: \.self) { kind in
            HStack(spacing: 5) {
                Circle().fill(kind.markColor).frame(width: 7, height: 7)
                Text(kind.title).lineLimit(1)
            }
            .fixedSize()
        }
    }
}

/// An icon button beside the month header.
private struct MonthControl: View {
    let systemImage: String
    let label: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(KyoPalette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct MonthDayCell: View {
    let day: MonthDay
    let select: () -> Void
    @ScaledMetric(relativeTo: .body) private var cellHeight = 52.0

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                Text("\(day.number)")
                    .font(.body)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(day.isToday ? Color(uiColor: .systemBackground) : Color.primary)
                    .frame(minWidth: 30, minHeight: 30)
                    .background {
                        if day.isToday { Circle().fill(KyoPalette.accent) }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(zip(MonthKind.allCases, day.marks)), id: \.0) { kind, mark in
                        MarkSlot(kind: kind, mark: mark)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight)
            .background {
                if day.isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KyoPalette.accent.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(KyoPalette.accent, lineWidth: 1.5)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityAddTraits(day.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("month-day-\(day.identifier)")
    }
}

/// One fixed slot in a day cell. An empty slot still takes its place so the others stay put.
private struct MarkSlot: View {
    let kind: MonthKind
    let mark: MonthMark

    var body: some View {
        ZStack {
            switch mark {
            case .empty: Color.clear
            case .filled: Circle().fill(kind.markColor)
            case .hollow: Circle().strokeBorder(kind.markColor, lineWidth: 1.5)
            }
        }
        .frame(width: 7, height: 7)
    }
}

private struct MonthDaySummaryView: View {
    let summary: MonthDaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.title)
                .font(.title3.weight(.semibold))
                .tracking(-0.4)
                .foregroundStyle(.primary)
                .accessibilityLabel(summary.accessibilityTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("month-summary-title")

            if summary.isEmpty {
                Text("Nothing on this day")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("month-summary-empty")
            }
            ForEach(summary.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(section.rows) { row in
                            Text(row.text)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 14)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("month-summary-section-\(section.kind.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension MonthKind {
    var title: String {
        switch self {
        case .events: "Events"
        case .tasks: "Tasks"
        case .habits: "Habits"
        case .memos: "Memos"
        }
    }

    /// Each kind has its own hue, but a mark's meaning comes from its slot; color is a second cue.
    var markColor: Color {
        switch self {
        case .events: Color(uiColor: .systemGray)
        case .tasks: KyoPalette.accent
        case .habits: Color(uiColor: .systemOrange)
        case .memos: Color(uiColor: .systemIndigo)
        }
    }
}
