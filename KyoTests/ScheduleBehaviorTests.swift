import XCTest

@MainActor
final class ScheduleBehaviorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")

    /// 2026-10-02 at the given time, UTC.
    private func date(_ hour: Int = 0, _ minute: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func timed(
        _ title: String, _ start: Date, until end: Date, id: String? = nil, occurrence: Date? = nil,
        calendarTitle: String = "Work", location: String? = nil
    ) -> ScheduleEvent {
        ScheduleEvent(
            id: ScheduleEventID(eventID: id ?? title, occurrenceDate: occurrence ?? start),
            title: title, start: start, end: end, location: location, calendarTitle: calendarTitle
        )
    }

    private func allDay(_ title: String, day: Int = 2) -> ScheduleEvent {
        ScheduleEvent(
            id: ScheduleEventID(eventID: title, occurrenceDate: date(day: day)),
            title: title, start: date(day: day), end: date(day: day + 1), isAllDay: true
        )
    }

    private func makeStore(
        _ service: FakeCalendarService, now: @escaping () -> Date, sleep: ScheduleStore.Sleep? = nil
    ) -> ScheduleStore {
        if let sleep {
            return ScheduleStore(service: service, now: now, calendar: calendar, locale: locale, sleep: sleep)
        }
        return ScheduleStore(service: service, now: now, calendar: calendar, locale: locale)
    }

    /// Polls until `condition` holds, since refreshes finish on their own tasks.
    private func eventually(_ message: String = "condition", _ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(message)")
    }

    // MARK: Authorization

    func testUndecidedAccessShowsTheConnectLineAndDoesNotReadEvents() async {
        let service = FakeCalendarService(access: .notDetermined, events: [timed("Standup", date(9), until: date(10))])
        let store = makeStore(service, now: { self.date(8) })
        XCTAssertFalse(store.showsSection, "nothing shows before the status is known")

        await store.refresh()

        XCTAssertTrue(store.showsSection)
        XCTAssertTrue(store.showsConnectPrompt)
        XCTAssertFalse(store.showsEvents)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(store.sectionNote, "Calendar")
        let fetched = await service.fetchedRanges
        XCTAssertTrue(fetched.isEmpty)
    }

    func testConnectRequestsAccessThenShowsTodaysEvents() async {
        let service = FakeCalendarService(access: .notDetermined, events: [timed("Standup", date(9), until: date(10))])
        let store = makeStore(service, now: { self.date(8) })
        await store.refresh()

        await store.connect()

        let requests = await service.requestCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(store.access, .fullAccess)
        XCTAssertFalse(store.showsConnectPrompt)
        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup"])
    }

    func testDecliningTheSystemPromptHidesTheSection() async {
        let service = FakeCalendarService(access: .notDetermined, accessAfterRequest: .denied)
        let store = makeStore(service, now: { self.date(8) })
        await store.refresh()

        await store.connect()

        XCTAssertEqual(store.access, .denied)
        XCTAssertFalse(store.showsSection)
    }

    func testConnectOnlyRequestsWhileUndecided() async {
        let service = FakeCalendarService(access: .fullAccess)
        let store = makeStore(service, now: { self.date(8) })
        await store.refresh()

        await store.connect()

        let requests = await service.requestCount
        XCTAssertEqual(requests, 0)
    }

    func testStatesWithoutReadAccessRenderNothingAndFetchNothing() async {
        for access in [CalendarAccess.denied, .restricted, .writeOnly] {
            let service = FakeCalendarService(access: access, events: [timed("Standup", date(9), until: date(10))])
            let store = makeStore(service, now: { self.date(8) })

            await store.refresh()

            XCTAssertEqual(store.access, access)
            XCTAssertFalse(store.showsSection, "\(access)")
            XCTAssertTrue(store.events.isEmpty, "\(access)")
        }
    }

    // MARK: Rows

    func testTimedEventsAreInTimeOrderAndAllDayEventsAreSeparate() async {
        let service = FakeCalendarService(events: [
            timed("Lunch", date(12, 30), until: date(13, 30)),
            allDay("Sam's birthday"),
            timed("Design review", date(10), until: date(11)),
            allDay("Holiday"),
            timed("Standup", date(9, 30), until: date(10)),
        ])
        let store = makeStore(service, now: { self.date(8) })

        await store.refresh()

        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup", "Design review", "Lunch"])
        XCTAssertEqual(Set(store.allDayEvents.map(\.title)), ["Sam's birthday", "Holiday"])
        XCTAssertEqual(store.sectionNote, "5 events")
    }

    func testAllDayEventsShareOneLine() async {
        let service = FakeCalendarService(events: [allDay("Sam's birthday"), allDay("Holiday")])
        let store = makeStore(service, now: { self.date(8) })

        await store.refresh()

        // Events that start together are ordered by title.
        XCTAssertEqual(store.allDayLine, "All day · Holiday, Sam's birthday")
        XCTAssertEqual(store.allDayAccessibilityLabel, "All day: Holiday, Sam's birthday")
    }

    func testNoAllDayEventsMeansNoAllDayLine() async {
        let service = FakeCalendarService(events: [timed("Standup", date(9), until: date(10))])
        let store = makeStore(service, now: { self.date(8) })

        await store.refresh()

        XCTAssertNil(store.allDayLine)
        XCTAssertNil(store.allDayAccessibilityLabel)
        XCTAssertEqual(store.sectionNote, "1 event")
    }

    func testAnEmptyDayShowsNothingScheduled() async {
        let store = makeStore(FakeCalendarService(), now: { self.date(8) })

        await store.refresh()

        XCTAssertTrue(store.showsSection)
        XCTAssertTrue(store.showsNothingScheduled)
        XCTAssertEqual(store.sectionNote, "Calendar")
    }

    func testRowsReadTheirTimeTitleAndCalendar() async throws {
        let service = FakeCalendarService(events: [timed("Design review", date(10), until: date(11), calendarTitle: "Work")])
        let store = makeStore(service, now: { self.date(8) })
        await store.refresh()

        let event = try XCTUnwrap(store.timedEvents.first)

        // Recent OS versions put a narrow no-break space before AM/PM.
        let spoken = store.accessibilityLabel(for: event).replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(spoken, "10:00 AM, Design review, Work calendar")
        XCTAssertEqual(store.timeText(for: event).replacingOccurrences(of: "\u{202F}", with: " "), "10:00 AM")
    }

    func testStartTimesFollowTheDeviceLocale() async throws {
        let service = FakeCalendarService(events: [timed("Design review", date(15), until: date(16))])
        let store = ScheduleStore(service: service, now: { self.date(8) }, calendar: calendar, locale: Locale(identifier: "de_DE"))
        await store.refresh()

        let event = try XCTUnwrap(store.timedEvents.first)

        XCTAssertEqual(store.timeText(for: event), "15:00")
    }

    func testAnUntitledEventStillGetsAName() async throws {
        let service = FakeCalendarService(events: [timed("  ", date(9), until: date(10), id: "blank")])
        let store = makeStore(service, now: { self.date(8) })
        await store.refresh()

        let event = try XCTUnwrap(store.timedEvents.first)

        XCTAssertTrue(store.accessibilityLabel(for: event).contains(", Untitled, "))
    }

    // MARK: Identity and Today's range

    func testEachOccurrenceOfARecurringEventIsADistinctRow() async {
        let service = FakeCalendarService(events: [
            timed("Standup", date(9), until: date(10), id: "series", occurrence: date(9)),
            timed("Standup", date(15), until: date(16), id: "series", occurrence: date(14)),
        ])
        let store = makeStore(service, now: { self.date(8) })

        await store.refresh()

        XCTAssertEqual(store.timedEvents.count, 2)
        XCTAssertEqual(Set(store.timedEvents.map(\.id)).count, 2)
        XCTAssertEqual(Set(store.timedEvents.map(\.id.eventID)), ["series"])
    }

    func testTodayRunsFromTheStartOfTodayToTheStartOfTomorrow() async {
        let service = FakeCalendarService()
        let store = makeStore(service, now: { self.date(15, 45) })

        await store.refresh()

        let fetched = await service.fetchedRanges
        XCTAssertEqual(fetched, [DateInterval(start: date(0), end: date(0, day: 3))])
        XCTAssertEqual(store.currentDate, date(0))
    }

    func testAnEventSpanningMidnightIsIncludedFromEitherSide() async {
        let overnight = timed("Overnight deploy", date(23, 0, day: 1), until: date(1, 0), calendarTitle: "Work")
        let leavingToday = timed("Flight", date(22), until: date(2, 0, day: 3))
        let service = FakeCalendarService(events: [overnight, leavingToday])
        let store = makeStore(service, now: { self.date(8) })

        await store.refresh()

        XCTAssertEqual(store.timedEvents.map(\.title), ["Overnight deploy", "Flight"])
    }

    func testEventsOutsideTodayAreLeftOut() async {
        let service = FakeCalendarService(events: [
            timed("Ended at midnight", date(22, 0, day: 1), until: date(0)),
            timed("Starts tomorrow", date(0, 0, day: 3), until: date(1, 0, day: 3)),
            timed("Today", date(9), until: date(10)),
        ])
        let store = makeStore(service, now: { self.date(8) })

        await store.refresh()

        XCTAssertEqual(store.timedEvents.map(\.title), ["Today"])
    }

    func testRowsKeepTheirPlainData() async throws {
        let blue = ScheduleColor(red: 0, green: 0, blue: 1)
        let event = ScheduleEvent(
            id: ScheduleEventID(eventID: "e", occurrenceDate: date(9)), title: "Design review",
            start: date(9), end: date(10), location: "Room 4", calendarID: "work", calendarTitle: "Work", calendarColor: blue
        )
        let store = makeStore(FakeCalendarService(events: [event]), now: { self.date(8) })

        await store.refresh()

        let row = try XCTUnwrap(store.events.first)
        XCTAssertEqual(row, event)
        XCTAssertEqual(row.location, "Room 4")
        XCTAssertEqual(row.calendarColor, blue)
    }

    // MARK: Refresh triggers

    func testAStoreChangeRefreshesTheEvents() async {
        let service = FakeCalendarService(events: [timed("Standup", date(9), until: date(10))])
        let store = makeStore(service, now: { self.date(8) })
        await store.refresh()
        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup"])

        let observing = Task { await store.observeChanges() }
        defer { observing.cancel() }
        await service.setEvents([timed("Standup", date(9), until: date(10)), timed("Dentist", date(14), until: date(15))])
        await service.emitChange()

        await eventually("the change to show") { store.timedEvents.map(\.title) == ["Standup", "Dentist"] }
    }

    func testReturningToTheForegroundPicksUpAnAccessChangeMadeInSettings() async {
        let service = FakeCalendarService(access: .denied, events: [timed("Standup", date(9), until: date(10))])
        let store = makeStore(service, now: { self.date(8) })
        await store.refresh()
        XCTAssertFalse(store.showsSection)

        await service.setAccess(.fullAccess)
        await store.refresh()

        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup"])
    }

    func testRefreshingAfterMidnightReadsTheNewDay() async {
        let service = FakeCalendarService(events: [
            timed("Today's", date(9), until: date(10)),
            timed("Tomorrow's", date(9, 0, day: 3), until: date(10, 0, day: 3)),
        ])
        var clock = date(23, 59)
        let store = makeStore(service, now: { clock })
        await store.refresh()
        XCTAssertEqual(store.timedEvents.map(\.title), ["Today's"])

        clock = date(0, 1, day: 3)
        await store.refresh()

        XCTAssertEqual(store.currentDate, date(0, 0, day: 3))
        XCTAssertEqual(store.timedEvents.map(\.title), ["Tomorrow's"])
    }

    func testTheDayBoundaryLoopRefreshesAtEachMidnight() async {
        let service = FakeCalendarService(events: [
            timed("Today's", date(9), until: date(10)),
            timed("Tomorrow's", date(9, 0, day: 3), until: date(10, 0, day: 3)),
        ])
        var clock = date(22)
        let sleeps = SleepRecorder()
        let store = makeStore(service, now: { clock }, sleep: { seconds in try await sleeps.sleep(seconds) })

        let loop = Task { await store.refreshAtEachDayBoundary() }
        defer { loop.cancel() }

        await eventually("the first sleep") { sleeps.durations.count == 1 }
        XCTAssertEqual(store.timedEvents.map(\.title), ["Today's"])
        XCTAssertEqual(sleeps.durations, [2 * 3600], "it sleeps until the next local midnight")

        clock = date(0, 0, day: 3)
        sleeps.wake()

        await eventually("the new day") { store.timedEvents.map(\.title) == ["Tomorrow's"] }
        XCTAssertEqual(store.currentDate, date(0, 0, day: 3))
    }

    func testAnOlderRefreshNeverOverwritesANewerOne() async {
        let service = FakeCalendarService(events: [timed("Standup", date(9), until: date(10))])
        let store = makeStore(service, now: { self.date(8) })

        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)

        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup"])
        XCTAssertEqual(store.events.count, 1)
    }
}

/// Stands in for `Task.sleep`: records each requested duration and waits until the test wakes it.
@MainActor
private final class SleepRecorder {
    private(set) var durations: [TimeInterval] = []
    private let wakeStream: AsyncStream<Void>
    private let wakeContinuation: AsyncStream<Void>.Continuation

    init() {
        (wakeStream, wakeContinuation) = AsyncStream.makeStream()
    }

    func sleep(_ seconds: TimeInterval) async throws {
        durations.append(seconds)
        for await _ in wakeStream { return }
        throw CancellationError()
    }

    func wake() { wakeContinuation.yield() }
}
