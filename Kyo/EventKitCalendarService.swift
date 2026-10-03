import EventKit
import UIKit

/// The live calendar service and the only code that imports EventKit. It owns the app's single
/// `EKEventStore`, created on first use so launch never touches the calendars, and turns events
/// into `Sendable` snapshots before they leave the actor.
actor EventKitCalendarService: CalendarService {
    private var storage: EKEventStore?

    private var store: EKEventStore {
        if let storage { return storage }
        let created = EKEventStore()
        storage = created
        return created
    }

    func authorizationStatus() -> CalendarAccess {
        Self.access(from: EKEventStore.authorizationStatus(for: .event))
    }

    func requestFullAccess() async -> CalendarAccess {
        guard authorizationStatus() == .notDetermined else { return authorizationStatus() }
        _ = try? await store.requestFullAccessToEvents()
        // A store that was used before access was granted must be reset to see events.
        store.reset()
        return authorizationStatus()
    }

    func events(from start: Date, to end: Date) -> [ScheduleEvent] {
        guard authorizationStatus() == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.compareStartDate(with: $1) == .orderedAscending }
            .map(Self.snapshot)
    }

    func changes() -> AsyncStream<Void> {
        let store = store
        return AsyncStream { continuation in
            let observer = ObserverToken(
                NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
                    continuation.yield()
                }
            )
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer.token)
            }
        }
    }

    private static func access(from status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        // `.writeOnly`, the deprecated `.authorized` and anything new: Kyo can't read events.
        default: .writeOnly
        }
    }

    private static func snapshot(_ event: EKEvent) -> ScheduleEvent {
        let eventID = event.eventIdentifier ?? event.calendarItemIdentifier
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScheduleEvent(
            id: ScheduleEventID(eventID: eventID, occurrenceDate: event.occurrenceDate ?? event.startDate),
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: (location?.isEmpty ?? true) ? nil : location,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            calendarColor: color(of: event.calendar?.cgColor) ?? .gray
        )
    }

    private static func color(of cgColor: CGColor?) -> ScheduleColor? {
        guard let cgColor else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(cgColor: cgColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return ScheduleColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// Carries a notification observer into the stream's termination handler, which is `@Sendable`.
private final class ObserverToken: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
}
