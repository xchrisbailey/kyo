import Foundation
import SwiftUI
import UIKit

/// A calendar service with canned authorization and events, for unit tests and for UI tests,
/// which select it with the `KYO_FAKE_CALENDAR` launch variable.
actor FakeCalendarService: CalendarService {
    private var access: CalendarAccess
    private let seeded: SeededEvents
    private var seededEvents: [ScheduleEvent] {
        get { seeded.events }
        set { seeded.events = newValue }
    }
    private var seededCalendars: [ScheduleCalendar]
    /// What the status becomes when `requestFullAccess()` is called while undecided.
    private let accessAfterRequest: CalendarAccess
    private let changeStream: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    /// Presents a stand-in detail sheet and records which occurrences were opened.
    nonisolated let eventDetails: any EventDetailPresenter
    nonisolated let fakeEventDetails: FakeEventDetailPresenter

    private(set) var requestCount = 0
    private(set) var fetchedRanges: [DateInterval] = []
    private(set) var calendarListCount = 0

    init(
        access: CalendarAccess = .fullAccess,
        events: [ScheduleEvent] = [],
        accessAfterRequest: CalendarAccess = .fullAccess,
        calendars: [ScheduleCalendar] = []
    ) {
        self.access = access
        let seeded = SeededEvents(events)
        self.seeded = seeded
        self.fakeEventDetails = FakeEventDetailPresenter(seeded: seeded)
        self.eventDetails = fakeEventDetails
        self.seededCalendars = calendars
        self.accessAfterRequest = accessAfterRequest
        (changeStream, changeContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func setAccess(_ access: CalendarAccess) { self.access = access }
    func setEvents(_ events: [ScheduleEvent]) { seededEvents = events }
    func setCalendars(_ calendars: [ScheduleCalendar]) { seededCalendars = calendars }

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

    func calendars() -> [ScheduleCalendar] {
        calendarListCount += 1
        return access == .fullAccess ? seededCalendars : []
    }

    func changes() -> AsyncStream<Void> { changeStream }
}

/// The fake's events, readable from the main actor by its detail presenter as well as from the
/// service's actor.
final class SeededEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ScheduleEvent]

    init(_ events: [ScheduleEvent]) { stored = events }

    var events: [ScheduleEvent] {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Stands in for the system event detail: a sheet with the event's title and time, which UI tests
/// can read. It records each occurrence it was asked to open, found or not.
@MainActor
final class FakeEventDetailPresenter: EventDetailPresenter {
    private let seeded: SeededEvents
    private(set) var requestedIDs: [ScheduleEventID] = []
    private var lastOnDone: (@MainActor () -> Void)?

    nonisolated init(seeded: SeededEvents) { self.seeded = seeded }

    /// Simulates the user tapping Done on the most recently opened details.
    func finishLastRequest() { lastOnDone?() }

    func viewController(for id: ScheduleEventID, onDone: @escaping @MainActor () -> Void) -> UIViewController? {
        requestedIDs.append(id)
        lastOnDone = onDone
        guard let event = seeded.events.first(where: { $0.id == id }) else { return nil }
        return UIHostingController(rootView: FakeEventDetailView(event: event, onDone: onDone))
    }
}

private struct FakeEventDetailView: View {

    @Environment(\.theme) private var theme
    let event: ScheduleEvent
    let onDone: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.displayTitle)
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("event-detail-title")
                Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("event-detail-time")
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                        .accessibilityIdentifier("event-detail-done")
                }
            }
        }
    }
}
