import XCTest

@MainActor
final class ScheduleEventDetailBehaviorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-02 at the given time, UTC.
    private func date(_ hour: Int = 0, _ minute: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func timed(_ title: String, _ start: Date, until end: Date, id: String? = nil) -> ScheduleEvent {
        ScheduleEvent(id: ScheduleEventID(eventID: id ?? title, occurrenceDate: start), title: title, start: start, end: end)
    }

    private func allDay(_ title: String) -> ScheduleEvent {
        ScheduleEvent(
            id: ScheduleEventID(eventID: title, occurrenceDate: date()),
            title: title, start: date(), end: date(day: 3), isAllDay: true
        )
    }

    private func makeStore(_ events: [ScheduleEvent]) async -> (ScheduleStore, FakeCalendarService) {
        let service = FakeCalendarService(events: events)
        let store = ScheduleStore(service: service, now: { self.date(8) }, calendar: calendar, locale: Locale(identifier: "en_US"))
        await store.refresh()
        return (store, service)
    }

    func testOpeningATimedEventPresentsItsDetails() async {
        let standup = timed("Standup", date(9), until: date(10))
        let (store, service) = await makeStore([standup, timed("Lunch", date(12), until: date(13))])

        store.open(standup.id)

        XCTAssertEqual(store.presentedDetail?.id, standup.id)
        XCTAssertFalse(store.isChoosingAllDayEvent)
        XCTAssertEqual(service.fakeEventDetails.requestedIDs, [standup.id])
    }

    func testOpeningARecurringEventAsksForThatOccurrence() async {
        let monday = timed("Weekly sync", date(9, 0, day: 2), until: date(10, 0, day: 2), id: "weekly")
        let nextDay = timed("Weekly sync", date(9, 0, day: 3), until: date(10, 0, day: 3), id: "weekly")
        let (store, service) = await makeStore([monday, nextDay])

        store.open(nextDay.id)

        let requested = service.fakeEventDetails.requestedIDs
        XCTAssertEqual(requested, [ScheduleEventID(eventID: "weekly", occurrenceDate: date(9, 0, day: 3))])
        XCTAssertNotEqual(requested.first, monday.id, "the first occurrence is not the one opened")
    }

    func testTheAllDayLineOpensALoneEventDirectly() async {
        let holiday = allDay("Holiday")
        let (store, service) = await makeStore([holiday, timed("Standup", date(9), until: date(10))])

        store.openAllDayEvents()

        XCTAssertEqual(store.presentedDetail?.id, holiday.id)
        XCTAssertFalse(store.isChoosingAllDayEvent)
        XCTAssertEqual(service.fakeEventDetails.requestedIDs, [holiday.id])
    }

    func testTheAllDayLineWithSeveralEventsShowsAChooserBeforeAnyDetails() async {
        let holiday = allDay("Holiday")
        let birthday = allDay("Sam's birthday")
        let (store, service) = await makeStore([holiday, birthday])

        store.openAllDayEvents()

        XCTAssertTrue(store.isChoosingAllDayEvent)
        XCTAssertNil(store.presentedDetail)
        XCTAssertTrue(service.fakeEventDetails.requestedIDs.isEmpty)

        store.open(birthday.id)

        XCTAssertEqual(store.presentedDetail?.id, birthday.id)
        XCTAssertTrue(store.isChoosingAllDayEvent, "the list stays under the details")
        XCTAssertEqual(service.fakeEventDetails.requestedIDs, [birthday.id])

        store.dismissDetail()

        XCTAssertNil(store.presentedDetail)
        XCTAssertTrue(store.isChoosingAllDayEvent, "closing the details returns to the list")

        store.dismissAllDayChooser()

        XCTAssertFalse(store.isChoosingAllDayEvent)
    }

    func testTheAllDayLineWithoutEventsDoesNothing() async {
        let (store, service) = await makeStore([timed("Standup", date(9), until: date(10))])

        store.openAllDayEvents()

        XCTAssertNil(store.presentedDetail)
        XCTAssertFalse(store.isChoosingAllDayEvent)
        XCTAssertTrue(service.fakeEventDetails.requestedIDs.isEmpty)
    }

    func testFinishingTheDetailsDismissesThem() async {
        let standup = timed("Standup", date(9), until: date(10))
        let (store, service) = await makeStore([standup])
        store.open(standup.id)

        service.fakeEventDetails.finishLastRequest()

        XCTAssertNil(store.presentedDetail)
    }

    func testAnEventThatIsGoneShowsNothingAndRefreshesTheSchedule() async {
        let standup = timed("Standup", date(9), until: date(10))
        let holiday = allDay("Holiday")
        let birthday = allDay("Sam's birthday")
        let (store, service) = await makeStore([standup, holiday, birthday])
        store.openAllDayEvents()
        await service.setEvents([standup])

        store.open(holiday.id)

        XCTAssertNil(store.presentedDetail)
        XCTAssertFalse(store.isChoosingAllDayEvent, "the list closes quietly too")
        for _ in 0..<500 where store.allDayEvents.count != 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.allDayEvents.isEmpty, "the Schedule refreshed without the deleted events")
        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup"])
    }
}
