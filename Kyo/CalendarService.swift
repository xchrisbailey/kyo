import Foundation

/// How far Kyo may read the device's calendars. Mirrors EventKit's authorization states without
/// importing it, so the Schedule model and its tests stay free of EventKit.
enum CalendarAccess: Sendable, Equatable {
    case notDetermined
    case fullAccess
    /// Write-only access, and the deprecated `.authorized`, both mean Kyo can't read events.
    case writeOnly
    case denied
    case restricted
}

/// A calendar's colour as plain components, so a snapshot stays `Sendable` and EventKit-free.
struct ScheduleColor: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static let gray = ScheduleColor(red: 0.56, green: 0.56, blue: 0.58)
}

/// One occurrence of an event: the event's id plus the occurrence date, so each recurrence of a
/// recurring event is its own row and can later be resolved to that occurrence.
struct ScheduleEventID: Hashable, Sendable {
    let eventID: String
    let occurrenceDate: Date
}

/// An event as a plain value, copied out of EventKit before it reaches the model or the views.
struct ScheduleEvent: Identifiable, Equatable, Sendable {
    let id: ScheduleEventID
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendarID: String
    let calendarTitle: String
    let calendarColor: ScheduleColor

    init(
        id: ScheduleEventID,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        calendarID: String = "calendar",
        calendarTitle: String = "Calendar",
        calendarColor: ScheduleColor = .gray
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
    }

    /// The title to show; an event with no title still needs a name.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

/// The boundary between Kyo and the device's calendars. The live implementation is the only code
/// that imports EventKit; tests and UI tests use `FakeCalendarService`.
protocol CalendarService: Sendable {
    /// The current authorization status. Never prompts.
    func authorizationStatus() async -> CalendarAccess

    /// Shows the system's full-access prompt when the status is `.notDetermined`, and returns the
    /// status afterwards.
    func requestFullAccess() async -> CalendarAccess

    /// The events that overlap `start` ..< `end`, sorted by start, empty without full access.
    func events(from start: Date, to end: Date) async -> [ScheduleEvent]

    /// Yields whenever the event store reports a change, which includes access changes.
    func changes() async -> AsyncStream<Void>

    /// Opens an event's details. Its screen is built on the main actor, so it sits beside the
    /// service rather than on it, and it shares the service's event store.
    nonisolated var eventDetails: any EventDetailPresenter { get }
}
