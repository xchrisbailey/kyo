import Foundation

/// A calendar service with canned authorization and events, for unit tests and for UI tests,
/// which select it with the `KYO_FAKE_CALENDAR` launch variable.
actor FakeCalendarService: CalendarService {
    private var access: CalendarAccess
    private var seededEvents: [ScheduleEvent]
    /// What the status becomes when `requestFullAccess()` is called while undecided.
    private let accessAfterRequest: CalendarAccess
    private let changeStream: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    private(set) var requestCount = 0
    private(set) var fetchedRanges: [DateInterval] = []

    init(
        access: CalendarAccess = .fullAccess,
        events: [ScheduleEvent] = [],
        accessAfterRequest: CalendarAccess = .fullAccess
    ) {
        self.access = access
        self.seededEvents = events
        self.accessAfterRequest = accessAfterRequest
        (changeStream, changeContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func setAccess(_ access: CalendarAccess) { self.access = access }
    func setEvents(_ events: [ScheduleEvent]) { seededEvents = events }

    /// Simulates the event store reporting a change.
    func emitChange() { changeContinuation.yield() }

    func authorizationStatus() -> CalendarAccess { access }

    func requestFullAccess() -> CalendarAccess {
        requestCount += 1
        if access == .notDetermined { access = accessAfterRequest }
        return access
    }

    func events(from start: Date, to end: Date) -> [ScheduleEvent] {
        fetchedRanges.append(DateInterval(start: start, end: end))
        guard access == .fullAccess else { return [] }
        return seededEvents
            .filter { event in
                event.start == event.end
                    ? (event.start >= start && event.start < end)
                    : (event.start < end && event.end > start)
            }
            .sorted { $0.start < $1.start }
    }

    func changes() -> AsyncStream<Void> { changeStream }
}
