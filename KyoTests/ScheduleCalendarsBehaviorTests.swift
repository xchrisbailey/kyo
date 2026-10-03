import XCTest

/// Choosing which calendars the Schedule reads: listing, grouping, hiding, and refetching.
@MainActor
final class ScheduleCalendarsBehaviorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private func date(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: hour))!
    }

    private let work = ScheduleCalendar(id: "work", title: "Work", accountTitle: "iCloud", accountType: .calDAV)
    private let personal = ScheduleCalendar(id: "personal", title: "Personal", accountTitle: "iCloud", accountType: .calDAV)
    private let holidays = ScheduleCalendar(id: "holidays", title: "Holidays", accountTitle: "Subscribed", accountType: .subscribed)

    private func event(_ id: String, _ hour: Int, in calendar: ScheduleCalendar) -> ScheduleEvent {
        ScheduleEvent(
            id: ScheduleEventID(eventID: id, occurrenceDate: date(hour)), title: id, start: date(hour), end: date(hour + 1),
            calendarID: calendar.id, calendarTitle: calendar.title
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "kyo.tests.schedule.calendars.\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func makeStore(_ service: FakeCalendarService, defaults: UserDefaults? = nil) -> ScheduleStore {
        ScheduleStore(
            service: service, now: { self.date(8) }, calendar: calendar, locale: Locale(identifier: "en_US"),
            defaults: defaults ?? makeDefaults(), openSettings: {}
        )
    }

    private func makeService(access: CalendarAccess = .fullAccess) -> FakeCalendarService {
        FakeCalendarService(
            access: access,
            events: [event("Standup", 9, in: work), event("Lunch", 12, in: personal), event("Parade", 15, in: holidays)],
            calendars: [work, personal, holidays]
        )
    }

    private func eventually(_ message: String, _ condition: @MainActor () async -> Bool) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(message)")
    }

    // MARK: Listing and defaults

    func testEveryCalendarIsShownByDefault() async {
        let store = makeStore(makeService())
        await store.refresh()

        XCTAssertEqual(store.calendars.map(\.id).sorted(), ["holidays", "personal", "work"])
        XCTAssertTrue(store.hiddenCalendarIDs.isEmpty)
        for id in ["work", "personal", "holidays"] { XCTAssertTrue(store.isCalendarVisible(id), id) }
        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup", "Lunch", "Parade"])
    }

    func testCalendarsAreGroupedByAccountSortedByTitle() async {
        let zebra = ScheduleCalendar(id: "z", title: "Zebra", accountTitle: "iCloud", accountType: .calDAV)
        let apple = ScheduleCalendar(id: "a", title: "apple", accountTitle: "iCloud", accountType: .calDAV)
        let birthdays = ScheduleCalendar(id: "b", title: "Birthdays", accountTitle: "Birthdays", accountType: .birthdays)
        let service = FakeCalendarService(calendars: [zebra, holidays, apple, birthdays, work])
        let store = makeStore(service)
        await store.refresh()

        XCTAssertEqual(store.calendarGroups.map(\.accountTitle), ["Birthdays", "iCloud", "Subscribed"])
        XCTAssertEqual(store.calendarGroups.map { $0.calendars.map(\.title) }, [["Birthdays"], ["apple", "Work", "Zebra"], ["Holidays"]])
    }

    func testAccountsWithTheSameTitleStaySeparateByType() async {
        let local = ScheduleCalendar(id: "l", title: "Home", accountTitle: "On My iPhone", accountType: .local)
        let other = ScheduleCalendar(id: "o", title: "Other", accountTitle: "On My iPhone", accountType: .exchange)
        let store = makeStore(FakeCalendarService(calendars: [local, other]))
        await store.refresh()

        XCTAssertEqual(store.calendarGroups.count, 2)
    }

    func testNoCalendarsAreListedWithoutFullAccess() async {
        for access in [CalendarAccess.notDetermined, .denied, .writeOnly, .restricted] {
            let store = makeStore(makeService(access: access))
            await store.refresh()

            XCTAssertTrue(store.calendars.isEmpty, "\(access)")
            XCTAssertTrue(store.calendarGroups.isEmpty, "\(access)")
        }
    }

    // MARK: Filtering

    func testHidingACalendarFiltersItsEventsOut() async {
        let store = makeStore(makeService())
        await store.refresh()

        store.setCalendar("work", visible: false)

        XCTAssertFalse(store.isCalendarVisible("work"))
        XCTAssertEqual(store.timedEvents.map(\.title), ["Lunch", "Parade"])
        XCTAssertEqual(store.sectionNote, "2 events")

        await store.refresh()
        XCTAssertEqual(store.timedEvents.map(\.title), ["Lunch", "Parade"])
    }

    func testShowingAHiddenCalendarBringsItsEventsBack() async {
        let store = makeStore(makeService())
        await store.refresh()
        store.setCalendar("work", visible: false)

        store.toggleCalendar("work")
        await store.refresh()

        XCTAssertTrue(store.isCalendarVisible("work"))
        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup", "Lunch", "Parade"])
    }

    func testHidingEveryCalendarLeavesNothingScheduled() async {
        let store = makeStore(makeService())
        await store.refresh()
        for id in ["work", "personal", "holidays"] { store.setCalendar(id, visible: false) }

        XCTAssertTrue(store.events.isEmpty)
        XCTAssertTrue(store.showsNothingScheduled)
    }

    func testUnknownHiddenIdsAreIgnored() async {
        let defaults = makeDefaults()
        defaults.set(["deleted-calendar"], forKey: ScheduleStore.hiddenCalendarIDsKey)
        let store = makeStore(makeService(), defaults: defaults)
        await store.refresh()

        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup", "Lunch", "Parade"])
        XCTAssertEqual(store.calendars.count, 3)
        XCTAssertFalse(store.isCalendarVisible("deleted-calendar"))
    }

    func testANewCalendarShowsByDefault() async {
        let service = makeService()
        let store = makeStore(service)
        await store.refresh()
        store.setCalendar("work", visible: false)

        let travel = ScheduleCalendar(id: "travel", title: "Travel", accountTitle: "iCloud", accountType: .calDAV)
        await service.setCalendars([work, personal, holidays, travel])
        await service.setEvents([event("Standup", 9, in: work), event("Flight", 11, in: travel)])
        await store.refresh()

        XCTAssertTrue(store.isCalendarVisible("travel"))
        XCTAssertEqual(store.timedEvents.map(\.title), ["Flight"])
        XCTAssertEqual(store.calendars.count, 4)
    }

    // MARK: Storage

    func testHiddenIdsAreStoredAsAnArrayOfStringsInDefaults() async {
        let defaults = makeDefaults()
        let store = makeStore(makeService(), defaults: defaults)
        await store.refresh()

        store.setCalendar("work", visible: false)
        store.setCalendar("holidays", visible: false)

        XCTAssertEqual(defaults.stringArray(forKey: ScheduleStore.hiddenCalendarIDsKey)?.sorted(), ["holidays", "work"])
    }

    func testTheSelectionSurvivesRelaunch() async {
        let defaults = makeDefaults()
        let first = makeStore(makeService(), defaults: defaults)
        await first.refresh()
        first.setCalendar("personal", visible: false)

        let second = makeStore(makeService(), defaults: defaults)
        await second.refresh()

        XCTAssertEqual(second.hiddenCalendarIDs, ["personal"])
        XCTAssertEqual(second.timedEvents.map(\.title), ["Standup", "Parade"])
    }

    func testShowingACalendarAgainRemovesItFromTheStoredIds() async {
        let defaults = makeDefaults()
        let store = makeStore(makeService(), defaults: defaults)
        await store.refresh()
        store.setCalendar("work", visible: false)

        store.setCalendar("work", visible: true)

        XCTAssertEqual(defaults.stringArray(forKey: ScheduleStore.hiddenCalendarIDsKey), [])
    }

    // MARK: Refetching

    func testChangingTheSelectionRefetchesTodaysEvents() async {
        let service = makeService()
        let store = makeStore(service)
        await store.refresh()
        let before = await service.fetchedRanges.count

        store.setCalendar("work", visible: false)

        await eventually("a refetch after the selection changed") { await service.fetchedRanges.count > before }
    }

    func testSettingTheSameVisibilityDoesNotRefetch() async {
        let service = makeService()
        let store = makeStore(service)
        await store.refresh()
        let before = await service.fetchedRanges.count

        store.setCalendar("work", visible: true)
        try? await Task.sleep(for: .milliseconds(100))

        let after = await service.fetchedRanges.count
        XCTAssertEqual(after, before)
    }

    func testTurningShowScheduleOffForgetsTheCalendars() async {
        let store = makeStore(makeService())
        await store.refresh()
        XCTAssertFalse(store.calendars.isEmpty)

        store.setShowsSchedule(false)

        XCTAssertTrue(store.calendars.isEmpty)
    }
}
