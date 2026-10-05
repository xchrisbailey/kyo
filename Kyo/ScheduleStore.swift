import Combine
import Foundation
import UIKit

/// Where a timed event stands against the clock: it has ended, is running, or is still to come.
enum ScheduleEventState: Equatable, Sendable {
    case past
    case inProgress
    case upcoming
}

/// One timed row as the section shows it, derived from the clock so views don't compute any of it.
struct ScheduleRowPresentation: Identifiable, Equatable {
    let event: ScheduleEvent
    let state: ScheduleEventState
    /// "Now", "Until 9:00 AM", or the start time.
    let timeText: String
    let accessibilityLabel: String
    /// The trimmed location, when there is one. Views decide whether it fits.
    let location: String?

    var id: ScheduleEventID { event.id }
}

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
    /// The device's event calendars, empty without full access. Read with Today's events.
    @Published private(set) var calendars: [ScheduleCalendar] = []
    /// The calendars the user hid, by id. Kept on this device only; a calendar that isn't here is
    /// shown, so new ones appear by default. Ids of calendars that no longer exist are ignored.
    @Published private(set) var hiddenCalendarIDs: Set<String>
    /// How many times Open Settings has been tapped.
    @Published private(set) var settingsOpenRequests = 0
    /// Whether the Open Settings control reports a tap to accessibility. UI tests turn this on,
    /// because they can't watch the Settings app open without leaving Kyo.
    let reportsSettingsRequests: Bool

    /// Where the Show schedule switch is stored.
    static let showsScheduleKey = "schedule.showsSchedule"
    /// Where the hidden calendar ids are stored, as an array of strings.
    static let hiddenCalendarIDsKey = "schedule.hiddenCalendarIDs"

    /// The clock reading that presentation (Now, past, the compact set) is derived from. It moves
    /// on every refresh and at each event boundary, so views re-render exactly when something changes.
    @Published private(set) var asOf: Date
    /// Whether the section shows every event. In memory only: it resets on relaunch and at midnight.
    @Published private(set) var isShowingMore = false

    /// The most in-progress or upcoming timed events the compact section shows.
    static let compactLimit = 3

    /// The event whose details are on screen, if any.
    @Published private(set) var presentedDetail: PresentedEventDetail?
    /// Whether the list of all-day events to choose from is on screen.
    @Published private(set) var isChoosingAllDayEvent = false

    private let service: any CalendarService
    private let now: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private let sleep: Sleep
    private let defaults: UserDefaults
    private let openSettingsAction: @MainActor () -> Void
    /// Orders overlapping refreshes: only the latest one may apply its result.
    private var refreshGeneration = 0
    /// Today's events before the hidden calendars are filtered out.
    private var fetchedEvents: [ScheduleEvent] = []

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
        self.hiddenCalendarIDs = Set(defaults.stringArray(forKey: Self.hiddenCalendarIDsKey) ?? [])
        self.currentDate = calendar.startOfDay(for: now())
        self.asOf = now()
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

    /// A time of day in the device's locale format.
    private func formatted(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
    }

    /// In progress when it has started and not yet ended, past once it has ended, upcoming otherwise.
    func state(of event: ScheduleEvent) -> ScheduleEventState {
        if event.end <= asOf { return .past }
        if event.start <= asOf { return .inProgress }
        return .upcoming
    }

    // MARK: Calendars

    /// The calendars grouped by account, accounts sorted by title and calendars by title.
    var calendarGroups: [ScheduleCalendarGroup] {
        Dictionary(grouping: calendars) { ScheduleCalendarGroup.Key(title: $0.accountTitle, type: $0.accountType) }
            .map { key, members in
                ScheduleCalendarGroup(
                    accountTitle: key.title, accountType: key.type,
                    calendars: members.sorted { Self.ordered($0.title, $0.id, before: $1.title, $1.id) }
                )
            }
            .sorted { Self.ordered($0.accountTitle, "\($0.accountType)", before: $1.accountTitle, "\($1.accountType)") }
    }

    func isCalendarVisible(_ id: String) -> Bool { !hiddenCalendarIDs.contains(id) }

    /// Shows or hides a calendar's events, remembers the choice, and refetches right away.
    func setCalendar(_ id: String, visible: Bool) {
        var hidden = hiddenCalendarIDs
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        guard hidden != hiddenCalendarIDs else { return }
        hiddenCalendarIDs = hidden
        defaults.set(hidden.sorted(), forKey: Self.hiddenCalendarIDsKey)
        // The list updates before the refetch lands.
        events = Self.sorted(visibleEvents(fetchedEvents))
        showLessIfNothingIsHidden()
        Task { await refresh() }
    }

    func toggleCalendar(_ id: String) { setCalendar(id, visible: !isCalendarVisible(id)) }

    private func visibleEvents(_ events: [ScheduleEvent]) -> [ScheduleEvent] {
        events.filter { !hiddenCalendarIDs.contains($0.calendarID) }
    }

    private static func ordered(_ lhs: String, _ lhsTie: String, before rhs: String, _ rhsTie: String) -> Bool {
        let order = lhs.localizedStandardCompare(rhs)
        return order == .orderedSame ? lhsTie < rhsTie : order == .orderedAscending
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
            isShowingMore = false
            fetchedEvents = []
            calendars = []
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

    /// "Now" while running, "Until 9:00 AM" for an event that started before Today and has ended,
    /// otherwise the start time. No countdowns.
    func timeText(for event: ScheduleEvent) -> String {
        switch state(of: event) {
        case .inProgress: "Now"
        case .past where event.start < currentDate: "Until \(formatted(event.end))"
        case .past, .upcoming: formatted(event.start)
        }
    }

    /// "10:00 AM, Design review, Work calendar", "Now, Design review, Work calendar", and for an
    /// event that has ended, "9:00 AM, Design review, Work calendar, ended".
    func accessibilityLabel(for event: ScheduleEvent) -> String {
        let label = "\(timeText(for: event)), \(event.displayTitle), \(event.calendarTitle) calendar"
        return state(of: event) == .past ? label + ", ended" : label
    }

    func presentation(of event: ScheduleEvent) -> ScheduleRowPresentation {
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScheduleRowPresentation(
            event: event, state: state(of: event), timeText: timeText(for: event),
            accessibilityLabel: accessibilityLabel(for: event),
            location: location?.isEmpty == false ? location : nil
        )
    }

    // MARK: Compact and showing more

    /// Every timed event in time order, past ones included.
    var allTimedRows: [ScheduleRowPresentation] { timedEvents.map(presentation(of:)) }

    /// Up to three timed events that are in progress or still to come, in time order.
    var compactRows: [ScheduleRowPresentation] {
        Array(allTimedRows.filter { $0.state != .past }.prefix(Self.compactLimit))
    }

    /// The timed rows on screen: the compact set, or all of them once showing more.
    var visibleRows: [ScheduleRowPresentation] { isShowingMore ? allTimedRows : compactRows }

    /// Timed events the compact section leaves out, upcoming and past. The all-day line isn't counted.
    var hiddenCount: Int { timedEvents.count - compactRows.count }

    /// "+3 more" while compact with anything hidden, otherwise `nil`.
    var moreText: String? { !isShowingMore && hiddenCount > 0 ? "+\(hiddenCount) more" : nil }

    /// "3 more events" for VoiceOver, since "+3" reads poorly.
    var moreAccessibilityLabel: String? {
        guard moreText != nil else { return nil }
        return hiddenCount == 1 ? "1 more event" : "\(hiddenCount) more events"
    }

    var showsShowLess: Bool { isShowingMore }

    /// Compact, with timed events that have all ended: "Nothing else today".
    var showsNothingElseToday: Bool {
        showsEvents && !isShowingMore && !timedEvents.isEmpty && compactRows.isEmpty
    }

    func showMore() {
        guard hiddenCount > 0 else { return }
        isShowingMore = true
    }

    func showLess() { isShowingMore = false }


    // MARK: Event details

    /// Opens an event's details. If the occurrence can't be found any more, for example because
    /// it was deleted since the Schedule was read, nothing is shown and the Schedule refreshes.
    func open(_ id: ScheduleEventID) {
        let detail = service.eventDetails.viewController(for: id) { [weak self] in
            self?.finishDetail(of: id)
        }
        guard let detail else {
            closeEventDetails()
            Task { await refresh() }
            return
        }
        presentedDetail = PresentedEventDetail(id: id, viewController: detail)
    }

    /// Taps the all-day line: one event opens directly, several open a list to choose from.
    func openAllDayEvents() {
        let allDay = allDayEvents
        if allDay.count == 1, let only = allDay.first {
            open(only.id)
        } else if allDay.count > 1 {
            isChoosingAllDayEvent = true
        }
    }

    /// Closes the details, leaving the all-day list up when that is where they were opened from.
    func dismissDetail() { presentedDetail = nil }

    /// Closes the all-day list, and with it any details opened from it.
    func dismissAllDayChooser() { closeEventDetails() }

    private func closeEventDetails() {
        presentedDetail = nil
        isChoosingAllDayEvent = false
    }

    private func finishDetail(of id: ScheduleEventID) {
        if presentedDetail?.id == id { presentedDetail = nil }
    }

    // MARK: Reading

    /// Re-reads the authorization status and, with full access, Today's events. Does nothing
    /// while Show schedule is off.
    func refresh() async {
        guard showsSchedule else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let clock = now()
        let today = calendar.startOfDay(for: clock)
        let status = await service.authorizationStatus()
        var fetched: [ScheduleEvent] = []
        var fetchedCalendars: [ScheduleCalendar] = []
        if status == .fullAccess, let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            fetched = await service.events(from: today, to: tomorrow)
            fetchedCalendars = await service.calendars()
        }
        guard generation == refreshGeneration else { return }
        access = status
        // A new day starts compact.
        if today != currentDate { isShowingMore = false }
        currentDate = today
        asOf = clock
        calendars = fetchedCalendars
        fetchedEvents = fetched
        events = Self.sorted(visibleEvents(fetched))
        showLessIfNothingIsHidden()
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

    /// Moves presentation forward at every event start and end while Today is on screen, until
    /// cancelled. It ignores boundaries after Today; the day-boundary loop covers midnight.
    func advanceAtEventBoundaries() async {
        while !Task.isCancelled {
            updateClock()
            guard let next = nextEventBoundary else { return }
            do {
                try await sleep(max(1, next.timeIntervalSince(now())))
            } catch {
                return
            }
        }
    }

    /// Re-reads the clock for presentation without re-reading events.
    func updateClock() {
        let clock = now()
        if clock != asOf { asOf = clock }
        showLessIfNothingIsHidden()
    }

    /// The next time a timed event starts or ends after `asOf`, within Today.
    var nextEventBoundary: Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate) else { return nil }
        return timedEvents
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > asOf && $0 < tomorrow }
            .min()
    }

    /// With nothing hidden there's no "Show less" row to leave, so don't keep showing more.
    private func showLessIfNothingIsHidden() {
        if isShowingMore && hiddenCount == 0 { isShowingMore = false }
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

/// The calendars of one account, as the Calendars screen lists them.
struct ScheduleCalendarGroup: Identifiable, Equatable {
    struct Key: Hashable {
        let title: String
        let type: ScheduleAccountType
    }

    let accountTitle: String
    let accountType: ScheduleAccountType
    let calendars: [ScheduleCalendar]

    var id: Key { Key(title: accountTitle, type: accountType) }
}
