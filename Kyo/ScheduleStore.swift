import Combine
import Foundation
import UIKit

/// Today's events as the Schedule section shows them. It reads through a `CalendarService`, never
/// stores events, and keeps the rows as plain data so presentation can be derived from a clock.
@MainActor
final class ScheduleStore: ObservableObject {
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void

    /// `nil` until the first read, so the section doesn't flash a prompt before the status is known.
    @Published private(set) var access: CalendarAccess?
    /// Today's events, all-day and timed, sorted by start. Empty without full access.
    @Published private(set) var events: [ScheduleEvent] = []
    @Published private(set) var currentDate: Date
    /// The Show schedule switch, kept on this device. Off hides the section and stops reading.
    @Published private(set) var showsSchedule: Bool
    /// How many times Open Settings has been tapped.
    @Published private(set) var settingsOpenRequests = 0
    /// Whether the Open Settings control reports a tap to accessibility. UI tests turn this on,
    /// because they can't watch the Settings app open without leaving Kyo.
    let reportsSettingsRequests: Bool

    /// Where the Show schedule switch is stored.
    static let showsScheduleKey = "schedule.showsSchedule"

    private let service: any CalendarService
    private let now: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private let sleep: Sleep
    private let defaults: UserDefaults
    private let openSettingsAction: @MainActor () -> Void
    /// Orders overlapping refreshes: only the latest one may apply its result.
    private var refreshGeneration = 0

    init(
        service: any CalendarService,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        locale: Locale = .current,
        sleep: @escaping Sleep = { seconds in try await Task.sleep(for: .seconds(seconds)) },
        defaults: UserDefaults = .standard,
        reportsSettingsRequests: Bool = false,
        openSettings: @escaping @MainActor () -> Void = ScheduleStore.openAppSettings
    ) {
        self.service = service
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.sleep = sleep
        self.defaults = defaults
        self.reportsSettingsRequests = reportsSettingsRequests
        self.openSettingsAction = openSettings
        self.showsSchedule = defaults.object(forKey: Self.showsScheduleKey) as? Bool ?? true
        self.currentDate = calendar.startOfDay(for: now())
    }

    // MARK: What the section shows

    /// Nothing renders while Show schedule is off, or before the first read.
    var showsSection: Bool { showsSchedule && access != nil }
    var showsConnectPrompt: Bool { showsSchedule && access == .notDetermined }
    /// "Calendar access is off", for denied access and for write-only access, which can't read events.
    var showsAccessOffLine: Bool { showsSchedule && (access == .denied || access == .writeOnly) }
    /// "Calendar access isn't available": the user can't change a restricted device.
    var showsUnavailableLine: Bool { showsSchedule && access == .restricted }
    var showsEvents: Bool { showsSchedule && access == .fullAccess }
    var showsNothingScheduled: Bool { showsEvents && events.isEmpty }

    var allDayEvents: [ScheduleEvent] { events.filter(\.isAllDay) }
    var timedEvents: [ScheduleEvent] { events.filter { !$0.isAllDay } }

    /// "All day · Sam's birthday, Holiday", or `nil` when no event lasts all day.
    var allDayLine: String? {
        let titles = allDayEvents.map(\.displayTitle)
        return titles.isEmpty ? nil : "All day · " + titles.joined(separator: ", ")
    }

    var allDayAccessibilityLabel: String? {
        let titles = allDayEvents.map(\.displayTitle)
        return titles.isEmpty ? nil : "All day: " + titles.joined(separator: ", ")
    }

    /// "3 events", or "Calendar" when there are none.
    var sectionNote: String {
        switch events.count {
        case 0: "Calendar"
        case 1: "1 event"
        default: "\(events.count) events"
        }
    }

    /// The event's start time in the device's locale format.
    func timeText(for event: ScheduleEvent) -> String {
        event.start.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
    }

    /// "10:00 AM, Design review, Work calendar".
    func accessibilityLabel(for event: ScheduleEvent) -> String {
        "\(timeText(for: event)), \(event.displayTitle), \(event.calendarTitle) calendar"
    }

    // MARK: Show schedule

    /// Turns the section on or off. Turning it on reads the current access state again.
    func setShowsSchedule(_ shows: Bool) {
        guard shows != showsSchedule else { return }
        showsSchedule = shows
        defaults.set(shows, forKey: Self.showsScheduleKey)
        if shows {
            Task { await refresh() }
        } else {
            // Drops any read still in flight, and forgets what was read.
            refreshGeneration += 1
            access = nil
            events = []
        }
    }

    /// The dismiss control on a prompt line.
    func dismissSchedule() { setShowsSchedule(false) }

    /// Opens Kyo's page in the Settings app, where the user can allow calendar access.
    func openSettings() {
        settingsOpenRequests += 1
        openSettingsAction()
    }

    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Reading

    /// Re-reads the authorization status and, with full access, Today's events. Does nothing
    /// while Show schedule is off.
    func refresh() async {
        guard showsSchedule else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let today = calendar.startOfDay(for: now())
        let status = await service.authorizationStatus()
        var fetched: [ScheduleEvent] = []
        if status == .fullAccess, let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            fetched = await service.events(from: today, to: tomorrow)
        }
        guard generation == refreshGeneration else { return }
        access = status
        currentDate = today
        events = Self.sorted(fetched)
    }

    /// Asks for full access, which shows the system prompt only while it's undecided.
    func connect() async {
        guard access == .notDetermined else { return }
        _ = await service.requestFullAccess()
        await refresh()
    }

    /// Re-reads whenever the event store reports a change, until cancelled.
    func observeChanges() async {
        for await _ in await service.changes() {
            if Task.isCancelled { return }
            await refresh()
        }
    }

    /// Refreshes now, then again at every local midnight until cancelled.
    func refreshAtEachDayBoundary() async {
        while !Task.isCancelled {
            await refresh()
            let today = calendar.startOfDay(for: now())
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
            do {
                try await sleep(max(1, tomorrow.timeIntervalSince(now())))
            } catch {
                return
            }
        }
    }

    private static func sorted(_ events: [ScheduleEvent]) -> [ScheduleEvent] {
        events.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            if lhs.id.eventID != rhs.id.eventID { return lhs.id.eventID < rhs.id.eventID }
            return lhs.id.occurrenceDate < rhs.id.occurrenceDate
        }
    }
}
