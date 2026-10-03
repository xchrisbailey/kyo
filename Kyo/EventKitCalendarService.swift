import EventKit
import EventKitUI
import UIKit

/// The app's single `EKEventStore`, created on first use so launch never touches the calendars.
/// The service reads Today's events from it off the main thread, and the event detail presenter
/// looks up one event on the main actor, so both share this one store.
final class EventKitStoreProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: EKEventStore?

    var store: EKEventStore {
        lock.lock()
        defer { lock.unlock() }
        if let storage { return storage }
        let created = EKEventStore()
        storage = created
        return created
    }
}

/// The live calendar service and the only code that imports EventKit. It reads the app's single
/// `EKEventStore` and turns events into `Sendable` snapshots before they leave the actor.
actor EventKitCalendarService: CalendarService {
    private let provider: EventKitStoreProvider
    nonisolated let eventDetails: any EventDetailPresenter

    private var store: EKEventStore { provider.store }

    init(provider: EventKitStoreProvider = EventKitStoreProvider()) {
        self.provider = provider
        self.eventDetails = EventKitEventDetailPresenter(provider: provider)
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

    func calendars() -> [ScheduleCalendar] {
        guard authorizationStatus() == .fullAccess else { return [] }
        return store.calendars(for: .event).map { calendar in
            ScheduleCalendar(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: Self.color(of: calendar.cgColor) ?? .gray,
                accountTitle: calendar.source?.title ?? "",
                accountType: calendar.source.map { Self.accountType(from: $0.sourceType) } ?? .other
            )
        }
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

    private static func accountType(from type: EKSourceType) -> ScheduleAccountType {
        switch type {
        case .local: .local
        case .exchange: .exchange
        case .calDAV: .calDAV
        case .mobileMe: .mobileMe
        case .subscribed: .subscribed
        case .birthdays: .birthdays
        @unknown default: .other
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

/// Shows an event with the system's event detail. It resolves the occurrence from its day's
/// events, because `event(withIdentifier:)` returns the first occurrence of a recurring event.
@MainActor
final class EventKitEventDetailPresenter: EventDetailPresenter {
    private let provider: EventKitStoreProvider
    private let calendar: Calendar

    nonisolated init(provider: EventKitStoreProvider, calendar: Calendar = .current) {
        self.provider = provider
        self.calendar = calendar
    }

    func viewController(for id: ScheduleEventID, onDone: @escaping @MainActor () -> Void) -> UIViewController? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, let event = occurrence(id) else { return nil }
        return EventDetailNavigationController(event: event, onDone: onDone)
    }

    /// The occurrence on `id.occurrenceDate`'s day with that event id and occurrence date, else
    /// the event itself, which is the first occurrence when the event recurs.
    private func occurrence(_ id: ScheduleEventID) -> EKEvent? {
        let store = provider.store
        let day = calendar.startOfDay(for: id.occurrenceDate)
        if let next = calendar.date(byAdding: .day, value: 1, to: day) {
            let predicate = store.predicateForEvents(withStart: day, end: next, calendars: nil)
            let match = store.events(matching: predicate).first { event in
                (event.eventIdentifier ?? event.calendarItemIdentifier) == id.eventID
                    && (event.occurrenceDate ?? event.startDate) == id.occurrenceDate
            }
            if let match { return match }
        }
        return store.event(withIdentifier: id.eventID)
    }
}

/// The system event detail inside a navigation controller, which carries its Done button. It is
/// its own delegate: `EKEventViewController` holds its delegate weakly, and this controller
/// outlives it.
@MainActor
private final class EventDetailNavigationController: UINavigationController, EKEventViewDelegate {
    private let onDone: @MainActor () -> Void

    init(event: EKEvent, onDone: @escaping @MainActor () -> Void) {
        self.onDone = onDone
        let detail = EKEventViewController()
        detail.event = event
        // Kyo never writes to the calendar. Invitation replies still work in the system sheet.
        detail.allowsEditing = false
        super.init(rootViewController: detail)
        detail.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    nonisolated func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
        MainActor.assumeIsolated { onDone() }
    }
}
