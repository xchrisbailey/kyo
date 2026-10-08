import Combine
import Foundation

/// How an event row looks in the Day summary, derived by the Schedule model so Month computes none of it.
struct MonthEventPresentation: Equatable, Sendable {
    /// "Now", "Until 9:00 AM", "All day", or the start time.
    let time: String
    let isInProgress: Bool
    /// An event that has ended, on Today only.
    let isDimmed: Bool
    let color: ScheduleColor
}

/// What Month shows for events: a mark on each day a visible event overlaps, and the day's events as
/// rows that open the event. It gets events only from the Schedule model, so Show schedule, access and
/// hidden calendars are applied there.
///
/// A content source answers at once but events are read asynchronously, so the source keeps the shown
/// month's events from the last read and answers from them. A read starts when the shown month changes
/// and whenever the Schedule model says what it would answer may have changed. Only the latest read may
/// land, so a read for a month the user has left never replaces the current month's events.
@MainActor
final class EventMonthContent: MonthContentSource {
    let kind = MonthKind.events
    private let schedule: ScheduleStore
    private let calendar: Calendar
    private let changeSubject = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()
    /// The first and last day Month last asked about, which is the month a read is for.
    private var shown: DateInterval?
    /// The events of the last read to land, and the month they were read for.
    private var cached: (month: DateInterval, events: [ScheduleEvent])?
    /// Orders overlapping reads: only the latest may land.
    private var readGeneration = 0

    init(schedule: ScheduleStore, calendar: Calendar) {
        self.schedule = schedule
        self.calendar = calendar
        schedule.visibleEventsDidChange
            .sink { [weak self] in
                // Answer from what is held under the new rules now, then read again.
                self?.changeSubject.send()
                self?.read()
            }
            .store(in: &subscriptions)
        schedule.presentationDidChange
            .sink { [weak self] in self?.changeSubject.send() }
            .store(in: &subscriptions)
    }

    /// Fires when a read lands, when the Schedule's rules change, and when the Schedule's clock moves.
    var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    func content(on days: [Date]) -> [Date: MonthKindDay] {
        guard let first = days.min(), let last = days.max() else { return [:] }
        let month = DateInterval(start: first, end: last)
        if shown != month {
            shown = month
            read()
        }
        // Events from another month's read, or any read while the Schedule hides events, aren't shown.
        guard schedule.showsEvents, let cached, cached.month == month else { return [:] }
        var result: [Date: MonthKindDay] = [:]
        for day in days {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let events = cached.events.filter { Self.event($0, overlaps: day, next) }
            if events.isEmpty { continue }
            // All-day events first, each group in the Schedule's time order.
            let ordered = events.filter(\.isAllDay) + events.filter { !$0.isAllDay }
            result[day] = MonthKindDay(
                mark: .filled,
                phrase: ordered.count == 1 ? "1 event" : "\(ordered.count) events",
                rows: ordered.map { row(for: $0, on: day) }
            )
        }
        return result
    }

    /// An event is on a day when it overlaps the span from the day's start to the next day's start.
    /// An event that ends at midnight, as an all-day event does, isn't on the day that follows.
    private static func event(_ event: ScheduleEvent, overlaps start: Date, _ next: Date) -> Bool {
        if event.start == event.end { return event.start >= start && event.start < next }
        return event.start < next && event.end > start
    }

    private func row(for event: ScheduleEvent, on day: Date) -> MonthSummaryRow {
        let id = "event-\(event.id.eventID)-\(event.id.occurrenceDate.timeIntervalSinceReferenceDate)"
        if event.isAllDay {
            return MonthSummaryRow(
                id: id, text: event.displayTitle, target: .event(event.id),
                accessibilityLabel: "All day: \(event.displayTitle)",
                event: MonthEventPresentation(time: "All day", isInProgress: false, isDimmed: false, color: event.calendarColor)
            )
        }
        let presentation = schedule.presentation(of: event, on: day)
        return MonthSummaryRow(
            id: id, text: event.displayTitle, target: .event(event.id),
            accessibilityLabel: presentation.accessibilityLabel,
            event: MonthEventPresentation(
                time: presentation.timeText, isInProgress: presentation.state == .inProgress,
                isDimmed: presentation.state == .past, color: event.calendarColor
            )
        )
    }

    /// Reads the shown month's events from the Schedule model and keeps them if this is still the latest read.
    private func read() {
        guard let month = shown, let end = calendar.date(byAdding: .day, value: 1, to: month.end) else { return }
        readGeneration += 1
        let generation = readGeneration
        Task { [weak self] in
            guard let events = await self?.schedule.visibleEvents(from: month.start, to: end) else { return }
            guard let self, generation == readGeneration else { return }
            cached = (month, events)
            changeSubject.send()
        }
    }
}
