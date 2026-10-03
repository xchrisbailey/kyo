import Foundation

/// Picks the calendar service for this launch: the fake when UI tests ask for one, otherwise the
/// live EventKit service.
enum CalendarServiceSelection {
    /// UI tests set this to `notDetermined`, `full`, `empty`, `denied`, `restricted` or `writeOnly`.
    /// `notDetermined` grants full access when Connect is tapped.
    static let fakeEnvironmentKey = "KYO_FAKE_CALENDAR"

    static func make() -> any CalendarService {
        let environment = ProcessInfo.processInfo.environment
        if let name = environment[fakeEnvironmentKey] {
            return fake(named: name)
        }
        // Isolated UI tests shouldn't depend on, or prompt for, the device's real calendars.
        if KyoModelContainer.isInMemoryRequested {
            return FakeCalendarService(access: .fullAccess)
        }
        return EventKitCalendarService()
    }

    /// The Schedule model for this launch. UI tests, which run on a fake service, get a throwaway
    /// Show schedule setting, and an Open Settings that records the tap instead of leaving Kyo.
    @MainActor
    static func makeScheduleStore() -> ScheduleStore {
        let environment = ProcessInfo.processInfo.environment
        guard environment[fakeEnvironmentKey] != nil || KyoModelContainer.isInMemoryRequested else {
            return ScheduleStore(service: make(), now: makeClock())
        }
        let suite = "kyo.schedule.ui-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return ScheduleStore(service: make(), now: makeClock(), defaults: defaults, reportsSettingsRequests: true, openSettings: {})
    }

    /// The clock the Schedule reads. A fake calendar pins it to 10:30 today so a seeded day looks
    /// the same at any hour: Standup has ended, Design review is in progress, Lunch is next.
    static func makeClock(calendar: Calendar = .current) -> () -> Date {
        guard ProcessInfo.processInfo.environment[fakeEnvironmentKey] != nil,
              let pinned = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: .now)
        else { return Date.init }
        return { pinned }
    }

    private static func fake(named name: String, calendar: Calendar = .current, now: Date = .now) -> FakeCalendarService {
        switch name {
        case "notDetermined":
            FakeCalendarService(access: .notDetermined, events: seededDay(calendar: calendar, now: now), calendars: seededCalendars)
        case "empty": FakeCalendarService(access: .fullAccess, calendars: seededCalendars)
        case "denied": FakeCalendarService(access: .denied)
        case "restricted": FakeCalendarService(access: .restricted)
        case "writeOnly": FakeCalendarService(access: .writeOnly)
        default: FakeCalendarService(access: .fullAccess, events: seededDay(calendar: calendar, now: now), calendars: seededCalendars)
        }
    }

    private static let workColor = ScheduleColor(red: 0.2, green: 0.4, blue: 0.9)
    private static let personalColor = ScheduleColor(red: 0.9, green: 0.4, blue: 0.2)
    private static let holidaysColor = ScheduleColor(red: 0.3, green: 0.7, blue: 0.4)

    /// Two accounts and three calendars: iCloud has Work and Personal, Subscribed has Holidays.
    private static let seededCalendars = [
        ScheduleCalendar(id: "work", title: "Work", color: workColor, accountTitle: "iCloud", accountType: .calDAV),
        ScheduleCalendar(id: "personal", title: "Personal", color: personalColor, accountTitle: "iCloud", accountType: .calDAV),
        ScheduleCalendar(id: "holidays", title: "Holidays", color: holidaysColor, accountTitle: "Subscribed", accountType: .subscribed),
    ]

    /// Two all-day events and three timed ones, given out of order. Two have a location, one short and one long.
    private static func seededDay(calendar: Calendar, now: Date) -> [ScheduleEvent] {
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        func timed(_ id: String, _ title: String, _ start: Date, hours: Double, in calendar: ScheduleCalendar, location: String? = nil) -> ScheduleEvent {
            ScheduleEvent(
                id: ScheduleEventID(eventID: id, occurrenceDate: start), title: title, start: start,
                end: start.addingTimeInterval(hours * 3600), location: location, calendarID: calendar.id, calendarTitle: calendar.title, calendarColor: calendar.color
            )
        }
        func allDay(_ id: String, _ title: String, in calendar: ScheduleCalendar) -> ScheduleEvent {
            ScheduleEvent(
                id: ScheduleEventID(eventID: id, occurrenceDate: today), title: title, start: today, end: tomorrow,
                isAllDay: true, calendarID: calendar.id, calendarTitle: calendar.title, calendarColor: calendar.color
            )
        }
        let work = seededCalendars[0], personal = seededCalendars[1], holidays = seededCalendars[2]
        return [
            timed("lunch", "Lunch", at(12, 30), hours: 1, in: personal, location: "The Corner Cafe, 1200 Long Street Name, Springfield"),
            allDay("birthday", "Sam's birthday", in: personal),
            timed("review", "Design review", at(10, 0), hours: 1, in: work, location: "Room 4"),
            allDay("holiday", "Holiday", in: holidays),
            timed("standup", "Standup", at(9, 30), hours: 0.5, in: work),
        ]
    }
}
