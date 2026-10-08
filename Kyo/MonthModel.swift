import Combine
import Foundation

/// The four kinds of content a day can hold, in the fixed order Month shows and reads them.
enum MonthKind: String, CaseIterable, Sendable {
    case events
    case tasks
    case habits
    case memos
}

/// What a kind's slot in a day cell shows. Only habits use `hollow`.
enum MonthMark: Equatable, Sendable {
    case empty
    case filled
    case hollow
}

/// One plain line in the Day summary.
struct MonthSummaryRow: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
}

/// What one kind holds on one day: its mark, the phrase a day cell reads aloud for it (such as
/// "2 events"), and its Day summary rows.
struct MonthKindDay: Equatable, Sendable {
    var mark: MonthMark
    var phrase: String?
    var rows: [MonthSummaryRow]

    init(mark: MonthMark = .empty, phrase: String? = nil, rows: [MonthSummaryRow] = []) {
        self.mark = mark
        self.phrase = phrase
        self.rows = rows
    }
}

/// Where one kind's content comes from. Month asks every source about the days it shows and asks
/// again whenever `changes` fires, so a source owns its kind's rules and Month owns the layout.
@MainActor
protocol MonthContentSource {
    var kind: MonthKind { get }
    /// Fires when what the source would answer has changed.
    var changes: AnyPublisher<Void, Never> { get }
    /// What the kind holds on each of `days` (each a start of day). A day it holds nothing on can be left out.
    func content(on days: [Date]) -> [Date: MonthKindDay]
}

struct MonthDay: Equatable {
    let date: Date
    let number: Int
    /// The day as `2026-10-06`, for identifying the cell.
    let identifier: String
    let isToday: Bool
    let isSelected: Bool
    /// One per kind, in `MonthKind.allCases` order.
    let marks: [MonthMark]
    let accessibilityLabel: String
}

/// A cell in the grid. A cell before the 1st or after the last day has no day.
struct MonthCell: Identifiable, Equatable {
    let id: Int
    let day: MonthDay?
}

struct MonthWeek: Identifiable, Equatable {
    let id: Int
    let cells: [MonthCell]
}

struct MonthSummarySection: Identifiable, Equatable {
    let kind: MonthKind
    let rows: [MonthSummaryRow]

    var id: MonthKind { kind }
}

/// The selected day's Day summary: its date, then a section for each kind that has something.
struct MonthDaySummary: Equatable {
    let title: String
    let accessibilityTitle: String
    let sections: [MonthSummarySection]

    var isEmpty: Bool { sections.isEmpty }
}

/// The month Month shows: its grid, each day's marks, which day is Today and which is selected,
/// and the selected day's Day summary. The view reads only this; each kind's content arrives
/// through a `MonthContentSource`.
@MainActor
final class MonthModel: ObservableObject {
    @Published private(set) var shownMonth: Date
    @Published private(set) var selectedDay: Date
    @Published private(set) var today: Date
    /// What each source reported for the shown month's days.
    @Published private var contents: [Date: [MonthKind: MonthKindDay]] = [:]

    private let now: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private let sources: [any MonthContentSource]
    private var subscriptions = Set<AnyCancellable>()

    init(
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        locale: Locale = .current,
        sources: [any MonthContentSource] = []
    ) {
        var calendar = calendar
        calendar.locale = locale
        let today = calendar.startOfDay(for: now())
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.sources = sources
        self.today = today
        self.selectedDay = today
        self.shownMonth = Self.startOfMonth(containing: today, in: calendar)
        for source in sources {
            source.changes
                .sink { [weak self] in self?.refresh() }
                .store(in: &subscriptions)
        }
        refresh()
    }

    // MARK: What the view shows

    /// "October 2026".
    var headerText: String {
        shownMonth.formatted(format.year().month(.wide))
    }

    /// The weekday row, starting at the locale's first weekday.
    var weekdayTitles: [String] {
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    var weeks: [MonthWeek] {
        let leading = (calendar.component(.weekday, from: shownMonth) - calendar.firstWeekday + 7) % 7
        let days = daysOfShownMonth
        var cells = (0..<leading).map { MonthCell(id: $0, day: nil) }
        cells += days.enumerated().map { MonthCell(id: leading + $0.offset, day: makeDay($0.element, number: $0.offset + 1)) }
        while cells.count % 7 != 0 { cells.append(MonthCell(id: cells.count, day: nil)) }
        return stride(from: 0, to: cells.count, by: 7).map { MonthWeek(id: $0 / 7, cells: Array(cells[$0..<$0 + 7])) }
    }

    var selectedSummary: MonthDaySummary {
        let content = contents[selectedDay] ?? [:]
        let sections = MonthKind.allCases.compactMap { kind -> MonthSummarySection? in
            guard let rows = content[kind]?.rows, !rows.isEmpty else { return nil }
            return MonthSummarySection(kind: kind, rows: rows)
        }
        return MonthDaySummary(
            title: selectedDay.formatted(format.weekday(.wide).month(.wide).day()),
            accessibilityTitle: selectedDay.formatted(format.weekday(.wide).month(.wide).day().year()),
            sections: sections
        )
    }

    // MARK: Changing what's shown

    /// Selects `day` if the shown month holds it. A cell outside the month can't be selected.
    func select(_ day: Date) {
        let start = calendar.startOfDay(for: day)
        guard daysOfShownMonth.contains(start) else { return }
        selectedDay = start
    }

    /// Shows the current month with Today selected, as Month opens each time.
    func showCurrentMonth() {
        let current = calendar.startOfDay(for: now())
        shownMonth = Self.startOfMonth(containing: current, in: calendar)
        selectedDay = current
        refresh()
    }

    /// Asks every source again about the shown month's days.
    func refresh() {
        today = calendar.startOfDay(for: now())
        let days = daysOfShownMonth
        let shown = Set(days)
        var result: [Date: [MonthKind: MonthKindDay]] = [:]
        for source in sources {
            for (day, content) in source.content(on: days) where shown.contains(day) {
                // Only events can be on a day after Today; anything else recorded there is ignored.
                guard day <= today || source.kind == .events else { continue }
                result[day, default: [:]][source.kind] = content
            }
        }
        contents = result
    }

    // MARK: Building days

    private var format: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private var daysOfShownMonth: [Date] {
        let count = calendar.range(of: .day, in: .month, for: shownMonth)?.count ?? 0
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: shownMonth) }
    }

    private func makeDay(_ date: Date, number: Int) -> MonthDay {
        let content = contents[date] ?? [:]
        let isToday = date == today
        let parts = [date.formatted(format.weekday(.wide).month(.wide).day())]
            + (isToday ? ["Today"] : [])
            + MonthKind.allCases.compactMap { content[$0]?.phrase }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return MonthDay(
            date: date,
            number: number,
            identifier: String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0),
            isToday: isToday,
            isSelected: date == selectedDay,
            marks: MonthKind.allCases.map { content[$0]?.mark ?? .empty },
            accessibilityLabel: parts.joined(separator: ", ")
        )
    }

    private static func startOfMonth(containing date: Date, in calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
