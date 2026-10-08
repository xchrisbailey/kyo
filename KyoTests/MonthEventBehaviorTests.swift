import XCTest

/// Events in Month, seen through the Month model on a real Schedule model over the fake calendar
/// service. Today is Tuesday 6 October 2026, noon, unless a test moves the clock.
@MainActor
final class MonthEventBehaviorTests: MonthTestCase {
    private let harness = MonthHarness(2026, 10, 6)

    private struct Fixture {
        let service: FakeCalendarService
        let schedule: ScheduleStore
        let model: MonthModel
    }

    private func makeFixture(
        access: CalendarAccess = .fullAccess,
        events: [ScheduleEvent] = [],
        calendars: [ScheduleCalendar] = [],
        wrapping wrap: (FakeCalendarService) -> any CalendarService = { $0 }
    ) async -> Fixture {
        let service = FakeCalendarService(access: access, events: events, calendars: calendars)
        let suite = "kyo.month-events.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let schedule = ScheduleStore(
            service: wrap(service), now: { self.harness.now }, calendar: harness.calendar, locale: harness.locale, defaults: defaults
        )
        let model = harness.makeModel(sources: [EventMonthContent(schedule: schedule, calendar: harness.calendar)])
        await schedule.refresh()
        // The app watches the event store for as long as it runs.
        let observer = Task { await schedule.observeChanges() }
        addTeardownBlock { observer.cancel() }
        return Fixture(service: service, schedule: schedule, model: model)
    }

    private func timed(
        _ title: String, on day: Int, from startHour: Int, to endHour: Int, month: Int = 10, calendarID: String = "work",
        location: String? = nil
    ) -> ScheduleEvent {
        let start = harness.date(2026, month, day, hour: startHour)
        return ScheduleEvent(
            id: ScheduleEventID(eventID: title, occurrenceDate: start), title: title,
            start: start, end: harness.date(2026, month, day, hour: endHour), location: location,
            calendarID: calendarID, calendarTitle: "Work"
        )
    }

    private func allDay(_ title: String, from firstDay: Int, through lastDay: Int, endingAtMidnight: Bool = true, month: Int = 10) -> ScheduleEvent {
        let start = harness.date(2026, month, firstDay, hour: 0)
        let end = endingAtMidnight
            ? harness.date(2026, month, lastDay + 1, hour: 0)
            : harness.date(2026, month, lastDay, hour: 23).addingTimeInterval(59 * 60 + 59)
        return ScheduleEvent(
            id: ScheduleEventID(eventID: title, occurrenceDate: start), title: title, start: start, end: end, isAllDay: true,
            calendarID: "holidays", calendarTitle: "Holidays"
        )
    }

    private func eventRows(in model: MonthModel) -> [MonthSummaryRow] {
        model.selectedSummary.sections.first { $0.kind == .events }?.rows ?? []
    }

    private func eventMark(onDay number: Int, in model: MonthModel) throws -> MonthMark {
        let index = try XCTUnwrap(MonthKind.allCases.firstIndex(of: .events))
        return try day(number, in: model).marks[index]
    }

    /// Times format with a narrow no-break space before AM and PM; tests compare with a plain one.
    private func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func times(of rows: [MonthSummaryRow]) -> [String] {
        rows.compactMap { plain($0.event?.time) }
    }

    // MARK: Marks

    func testADayWithAVisibleEventShowsTheEventMarkAndADayWithNoneLeavesTheSlotEmpty() async throws {
        let f = await makeFixture(events: [timed("Standup", on: 8, from: 9, to: 10)])

        try await eventually("the event mark") { try eventMark(onDay: 8, in: f.model) == .filled }
        XCTAssertEqual(try eventMark(onDay: 7, in: f.model), .empty)
        XCTAssertEqual(try eventMark(onDay: 9, in: f.model), .empty)
    }

    func testAMultiDayEventMarksEveryDayItOverlapsAndAnAllDayEventCounts() async throws {
        let overnight = ScheduleEvent(
            id: ScheduleEventID(eventID: "Offsite", occurrenceDate: harness.date(2026, 10, 12, hour: 22)),
            title: "Offsite", start: harness.date(2026, 10, 12, hour: 22), end: harness.date(2026, 10, 14, hour: 9)
        )
        let f = await makeFixture(events: [overnight, allDay("Holiday", from: 20, through: 20)])

        try await eventually("the marks") { try eventMark(onDay: 14, in: f.model) == .filled }
        for number in [12, 13, 14, 20] {
            XCTAssertEqual(try eventMark(onDay: number, in: f.model), .filled, "day \(number)")
        }
        for number in [11, 15, 19, 21] {
            XCTAssertEqual(try eventMark(onDay: number, in: f.model), .empty, "day \(number)")
        }
    }

    func testAnAllDayEventEndingAtMidnightOrAtTheEndOfItsLastDayDoesNotMarkTheNextDay() async throws {
        // The fake's all-day events end at the next midnight; EventKit's end at the end of the last day.
        let f = await makeFixture(events: [
            allDay("Fake style", from: 8, through: 9, endingAtMidnight: true),
            allDay("EventKit style", from: 15, through: 16, endingAtMidnight: false),
        ])

        try await eventually("the marks") { try eventMark(onDay: 16, in: f.model) == .filled }
        XCTAssertEqual(try eventMark(onDay: 9, in: f.model), .filled)
        XCTAssertEqual(try eventMark(onDay: 10, in: f.model), .empty)
        XCTAssertEqual(try eventMark(onDay: 17, in: f.model), .empty)
    }

    func testAnEventEndingAtMidnightDoesNotMarkTheFollowingDay() async throws {
        let late = ScheduleEvent(
            id: ScheduleEventID(eventID: "Late", occurrenceDate: harness.date(2026, 10, 8, hour: 20)),
            title: "Late", start: harness.date(2026, 10, 8, hour: 20), end: harness.date(2026, 10, 9, hour: 0)
        )
        let f = await makeFixture(events: [late])

        try await eventually("the mark") { try eventMark(onDay: 8, in: f.model) == .filled }
        XCTAssertEqual(try eventMark(onDay: 9, in: f.model), .empty)
    }

    // MARK: Hidden calendars, Show schedule and access

    func testEventsFromHiddenCalendarsProduceNoMarkAndNoRow() async throws {
        let f = await makeFixture(events: [
            timed("Standup", on: 8, from: 9, to: 10, calendarID: "work"),
            timed("Movie", on: 9, from: 19, to: 21, calendarID: "personal"),
        ])
        f.schedule.setCalendar("personal", visible: false)

        try await eventually("the Movie mark to go") { try eventMark(onDay: 9, in: f.model) == .empty }
        XCTAssertEqual(try eventMark(onDay: 8, in: f.model), .filled)
        f.model.select(harness.date(2026, 10, 9, hour: 0))
        XCTAssertEqual(eventRows(in: f.model), [])
    }

    func testHidingACalendarRemovesItsMarksAndRowsAtOnceWithoutWaitingForTheNextRead() async throws {
        let f = await makeFixture(events: [
            timed("Standup", on: 6, from: 13, to: 14, calendarID: "work"),
            timed("Movie", on: 6, from: 19, to: 21, calendarID: "personal"),
            timed("Dinner", on: 9, from: 19, to: 21, calendarID: "personal"),
        ])
        try await eventually("the marks and rows") {
            try eventMark(onDay: 9, in: f.model) == .filled && eventRows(in: f.model).count == 2
        }

        f.schedule.setCalendar("personal", visible: false)

        // Nothing is awaited: the read that setCalendar starts hasn't landed yet.
        XCTAssertEqual(try eventMark(onDay: 9, in: f.model), .empty)
        XCTAssertEqual(try eventMark(onDay: 6, in: f.model), .filled, "the visible calendar's event keeps its mark")
        XCTAssertEqual(eventRows(in: f.model).map(\.text), ["Standup"])
        XCTAssertEqual(try day(6, in: f.model).accessibilityLabel, "Tuesday, October 6, Today, 1 event")
    }

    func testWithShowScheduleOffThereAreNoMarksNoRowsAndNothingIsRead() async throws {
        let f = await makeFixture(events: [timed("Standup", on: 8, from: 9, to: 10)])
        try await eventually("the mark") { try eventMark(onDay: 8, in: f.model) == .filled }

        f.schedule.setShowsSchedule(false)

        XCTAssertEqual(try eventMark(onDay: 8, in: f.model), .empty, "gone at once")
        f.model.select(harness.date(2026, 10, 8, hour: 0))
        XCTAssertEqual(eventRows(in: f.model), [])
        XCTAssertEqual(try day(8, in: f.model).accessibilityLabel, "Thursday, October 8")
        let before = await f.service.fetchedRanges.count
        f.model.showNextMonth()
        f.model.showPreviousMonth()
        try? await Task.sleep(for: .milliseconds(100))
        let after = await f.service.fetchedRanges.count
        XCTAssertEqual(before, after, "Month read no events with Show schedule off")
        XCTAssertEqual(try eventMark(onDay: 8, in: f.model), .empty)

        f.schedule.setShowsSchedule(true)
        try await eventually("the mark to return") { try eventMark(onDay: 8, in: f.model) == .filled }
    }

    func testWithAnyAccessButFullThereAreNoMarksNoRowsAndNoPrompt() async throws {
        for access in [CalendarAccess.notDetermined, .denied, .restricted, .writeOnly] {
            let f = await makeFixture(access: access, events: [timed("Standup", on: 6, from: 9, to: 10)])
            f.model.showNextMonth()
            f.model.showPreviousMonth()
            try? await Task.sleep(for: .milliseconds(50))

            XCTAssertEqual(try eventMark(onDay: 6, in: f.model), .empty, "\(access)")
            XCTAssertEqual(eventRows(in: f.model), [], "\(access)")
            let requests = await f.service.requestCount
            XCTAssertEqual(requests, 0, "Month never asks for access (\(access))")
            XCTAssertTrue(f.model.selectedSummary.isEmpty, "\(access)")
        }
    }

    // MARK: Day summary

    func testTheDaySummaryListsAllDayEventsFirstThenTimedEventsByStart() async throws {
        let f = await makeFixture(events: [
            timed("Lunch", on: 8, from: 12, to: 13),
            timed("Standup", on: 8, from: 9, to: 10),
            allDay("Holiday", from: 8, through: 8),
        ])
        try await eventually("the rows") { try eventMark(onDay: 8, in: f.model) == .filled }

        f.model.select(harness.date(2026, 10, 8, hour: 0))

        let rows = eventRows(in: f.model)
        XCTAssertEqual(rows.map(\.text), ["Holiday", "Standup", "Lunch"])
        XCTAssertEqual(times(of: rows), ["All day", "9:00 AM", "12:00 PM"])
        XCTAssertEqual(rows.first?.accessibilityLabel, "All day: Holiday")
        XCTAssertEqual(try day(8, in: f.model).accessibilityLabel, "Thursday, October 8, 3 events")
    }

    func testAFutureDayListsItsEventsAndNothingElse() async throws {
        let f = await makeFixture(events: [timed("Dentist", on: 20, from: 15, to: 16)])
        try await eventually("the mark") { try eventMark(onDay: 20, in: f.model) == .filled }

        f.model.select(harness.date(2026, 10, 20, hour: 0))

        XCTAssertEqual(f.model.selectedSummary.sections.map(\.kind), [.events])
        XCTAssertEqual(times(of: eventRows(in: f.model)), ["3:00 PM"])
        XCTAssertEqual(try day(20, in: f.model).accessibilityLabel, "Tuesday, October 20, 1 event")
    }

    func testAPastDaysTimedRowShowsItsStartTimeUndimmedAndIsNeverReadAsEndedOrUntil() async throws {
        let f = await makeFixture(events: [timed("Review", on: 2, from: 9, to: 10)])
        try await eventually("the mark") { try eventMark(onDay: 2, in: f.model) == .filled }

        f.model.select(harness.date(2026, 10, 2, hour: 0))

        let row = try XCTUnwrap(eventRows(in: f.model).first)
        XCTAssertEqual(plain(row.event?.time), "9:00 AM")
        XCTAssertEqual(row.event?.isDimmed, false)
        XCTAssertEqual(row.event?.isInProgress, false)
        XCTAssertEqual(plain(row.accessibilityLabel), "9:00 AM, Review, Work calendar")
    }

    func testAMultiDayEventShowsItsStartTimeOnTheLaterDayItIsOpenedFrom() async throws {
        let overnight = ScheduleEvent(
            id: ScheduleEventID(eventID: "Offsite", occurrenceDate: harness.date(2026, 10, 2, hour: 22)),
            title: "Offsite", start: harness.date(2026, 10, 2, hour: 22), end: harness.date(2026, 10, 3, hour: 9)
        )
        let f = await makeFixture(events: [overnight])
        try await eventually("the mark") { try eventMark(onDay: 3, in: f.model) == .filled }

        f.model.select(harness.date(2026, 10, 3, hour: 0))

        let row = try XCTUnwrap(eventRows(in: f.model).first)
        XCTAssertEqual(plain(row.event?.time), "10:00 PM")
        XCTAssertEqual(row.event?.isDimmed, false)
        XCTAssertFalse(row.accessibilityLabel?.contains("ended") ?? true)
    }

    func testTodaysRowsMatchTheScheduleIncludingNowUntilDimmingAndEnded() async throws {
        // Noon: Standup has ended, Review is running, Dinner is still to come, and the Offsite started yesterday.
        let offsite = ScheduleEvent(
            id: ScheduleEventID(eventID: "Offsite", occurrenceDate: harness.date(2026, 10, 5, hour: 20)),
            title: "Offsite", start: harness.date(2026, 10, 5, hour: 20), end: harness.date(2026, 10, 6, hour: 8),
            calendarTitle: "Work"
        )
        let f = await makeFixture(events: [
            timed("Dinner", on: 6, from: 19, to: 21),
            timed("Review", on: 6, from: 11, to: 13),
            timed("Standup", on: 6, from: 9, to: 10),
            offsite,
        ])
        try await eventually("the rows") { eventRows(in: f.model).count == 4 }

        let rows = eventRows(in: f.model)
        XCTAssertEqual(rows.map(\.text), ["Offsite", "Standup", "Review", "Dinner"])
        XCTAssertEqual(times(of: rows), ["Until 8:00 AM", "9:00 AM", "Now", "7:00 PM"])
        XCTAssertEqual(rows.compactMap(\.event?.isDimmed), [true, true, false, false])
        XCTAssertEqual(rows.compactMap(\.event?.isInProgress), [false, false, true, false])
        // Each row reads exactly as the Schedule reads it.
        XCTAssertEqual(rows.compactMap(\.accessibilityLabel), f.schedule.timedEvents.map(f.schedule.accessibilityLabel(for:)))
        XCTAssertEqual(plain(rows.last?.accessibilityLabel), "7:00 PM, Dinner, Work calendar")
        XCTAssertTrue(rows[1].accessibilityLabel?.hasSuffix(", ended") ?? false)
        XCTAssertEqual(try day(6, in: f.model).accessibilityLabel, "Tuesday, October 6, Today, 4 events")
    }

    func testTodaysRowsMoveOnWhenTheScheduleClockMoves() async throws {
        let f = await makeFixture(events: [timed("Review", on: 6, from: 13, to: 14)])
        try await eventually("the row") { plain(eventRows(in: f.model).first?.event?.time) == "1:00 PM" }

        harness.setNow(harness.date(2026, 10, 6, hour: 13))
        f.schedule.updateClock()

        XCTAssertEqual(eventRows(in: f.model).first?.event?.time, "Now")
        XCTAssertEqual(eventRows(in: f.model).first?.event?.isInProgress, true)

        harness.setNow(harness.date(2026, 10, 6, hour: 15))
        f.schedule.updateClock()
        XCTAssertEqual(eventRows(in: f.model).first?.event?.isDimmed, true)
    }

    func testARowOpensTheOccurrenceOfTheDayItIsOpenedFrom() async throws {
        let monday = timed("Weekly sync", on: 5, from: 9, to: 10)
        let tuesday = ScheduleEvent(
            id: ScheduleEventID(eventID: "Weekly sync", occurrenceDate: harness.date(2026, 10, 12, hour: 9)),
            title: "Weekly sync", start: harness.date(2026, 10, 12, hour: 9), end: harness.date(2026, 10, 12, hour: 10)
        )
        let f = await makeFixture(events: [monday, tuesday])
        try await eventually("the mark") { try eventMark(onDay: 12, in: f.model) == .filled }
        f.model.select(harness.date(2026, 10, 12, hour: 0))
        let row = try XCTUnwrap(eventRows(in: f.model).first)

        guard case .event(let id)? = row.target else { return XCTFail("an event row opens its event") }
        f.schedule.open(id)

        XCTAssertEqual(id, tuesday.id)
        XCTAssertEqual(f.schedule.presentedDetail?.id, tuesday.id)
        XCTAssertEqual(f.service.fakeEventDetails.requestedIDs, [tuesday.id])
    }

    // MARK: Location

    func testTodaysRowCarriesTheTrimmedLocationTheScheduleRowDoes() async throws {
        let f = await makeFixture(events: [
            timed("Review", on: 6, from: 13, to: 14, location: "  Room 4 \n"),
            timed("Call", on: 6, from: 15, to: 16, location: "   "),
            timed("Lunch", on: 6, from: 17, to: 18),
        ])
        try await eventually("the rows") { eventRows(in: f.model).count == 3 }

        let rows = eventRows(in: f.model)
        XCTAssertEqual(rows.map(\.text), ["Review", "Call", "Lunch"])
        XCTAssertEqual(rows.map { $0.event?.location }, ["Room 4", nil, nil])
        XCTAssertEqual(rows.map { $0.event?.location }, f.schedule.allTimedRows.map(\.location))
    }

    func testAnotherDaysRowCarriesTheTrimmedLocation() async throws {
        let f = await makeFixture(events: [
            timed("Review", on: 8, from: 9, to: 10, location: " Room 4 "),
            timed("Call", on: 8, from: 11, to: 12, location: ""),
        ])
        try await eventually("the mark") { try eventMark(onDay: 8, in: f.model) == .filled }

        f.model.select(harness.date(2026, 10, 8, hour: 0))

        XCTAssertEqual(eventRows(in: f.model).map { $0.event?.location }, ["Room 4", nil])
    }

    // MARK: Refetching

    func testMarksAndRowsUpdateAfterTheEventStoreChanges() async throws {
        let f = await makeFixture(events: [timed("Standup", on: 8, from: 9, to: 10)])
        try await eventually("the mark") { try eventMark(onDay: 8, in: f.model) == .filled }

        await f.service.setEvents([timed("Standup", on: 9, from: 9, to: 10)])
        await f.service.emitChange()

        try await eventually("the mark to move") { try eventMark(onDay: 9, in: f.model) == .filled }
        XCTAssertEqual(try eventMark(onDay: 8, in: f.model), .empty)
    }

    func testMovingToAnotherMonthShowsThatMonthsEvents() async throws {
        let f = await makeFixture(events: [
            timed("Standup", on: 8, from: 9, to: 10),
            timed("Trip", on: 14, from: 9, to: 17, month: 11),
        ])
        try await eventually("the October mark") { try eventMark(onDay: 8, in: f.model) == .filled }

        f.model.showNextMonth()

        try await eventually("the November mark") { try eventMark(onDay: 14, in: f.model) == .filled }
        XCTAssertEqual(try eventMark(onDay: 8, in: f.model), .empty)
        f.model.showPreviousMonth()
        try await eventually("the October mark again") { try eventMark(onDay: 8, in: f.model) == .filled }
    }

    func testReturningToTheForegroundPicksUpEventsAddedMeanwhile() async throws {
        let f = await makeFixture()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(try eventMark(onDay: 8, in: f.model), .empty)

        await f.service.setEvents([timed("Standup", on: 8, from: 9, to: 10)])
        // What the app does when the scene becomes active.
        f.model.refresh()
        await f.schedule.refresh()

        try await eventually("the mark") { try eventMark(onDay: 8, in: f.model) == .filled }
    }

    func testChangingTheCalendarSelectionUpdatesMonth() async throws {
        let f = await makeFixture(events: [timed("Movie", on: 9, from: 19, to: 21, calendarID: "personal")])
        try await eventually("the mark") { try eventMark(onDay: 9, in: f.model) == .filled }

        f.schedule.setCalendar("personal", visible: false)
        try await eventually("the mark to go") { try eventMark(onDay: 9, in: f.model) == .empty }

        f.schedule.setCalendar("personal", visible: true)
        try await eventually("the mark to return") { try eventMark(onDay: 9, in: f.model) == .filled }
    }

    func testAReadForAMonthTheUserHasLeftNeverReplacesTheCurrentMonth() async throws {
        let gate = ReadGate()
        let f = await makeFixture(
            events: [
                timed("Standup", on: 8, from: 9, to: 10),
                timed("Trip", on: 14, from: 9, to: 17, month: 11),
                timed("Party", on: 3, from: 20, to: 23, month: 12),
            ],
            wrapping: { GatedCalendarService(wrapping: $0, gate: gate) }
        )
        try await eventually("the October mark") { try eventMark(onDay: 8, in: f.model) == .filled }

        // Hold the next reads: November's is asked for first, then the user moves on to December.
        gate.hold()
        f.model.showNextMonth()
        try await eventually("November's read to be held") { gate.heldCount >= 1 }
        let heldForNovember = gate.heldCount
        f.model.showNextMonth()
        try await eventually("December's read to be held") { gate.heldCount > heldForNovember }
        // December's read lands first and November's, the stale one, lands last.
        gate.release(oldestFirst: false)

        try await eventually("December's mark") { try eventMark(onDay: 3, in: f.model) == .filled }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(f.model.headerText, "December 2026")
        XCTAssertEqual(try eventMark(onDay: 3, in: f.model), .filled, "November's late read doesn't replace December's")
        XCTAssertEqual(try eventMark(onDay: 14, in: f.model), .empty)
    }
}

/// Holds reads of events until the test lets them go, to land them out of order.
@MainActor
final class ReadGate {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var isHolding = false

    var heldCount: Int { held.count }

    func hold() { isHolding = true }

    func release(oldestFirst: Bool) {
        isHolding = false
        let waiting = held
        held = []
        for continuation in (oldestFirst ? waiting : waiting.reversed()) { continuation.resume() }
    }

    func passOrWait() async {
        guard isHolding else { return }
        await withCheckedContinuation { held.append($0) }
    }
}

/// A calendar service whose event reads wait at a `ReadGate`.
struct GatedCalendarService: CalendarService {
    let wrapped: FakeCalendarService
    let gate: ReadGate

    init(wrapping wrapped: FakeCalendarService, gate: ReadGate) {
        self.wrapped = wrapped
        self.gate = gate
    }

    func authorizationStatus() async -> CalendarAccess { await wrapped.authorizationStatus() }
    func requestFullAccess() async -> CalendarAccess { await wrapped.requestFullAccess() }
    func events(from start: Date, to end: Date) async -> [ScheduleEvent] {
        let events = await wrapped.events(from: start, to: end)
        await gate.passOrWait()
        return events
    }
    func calendars() async -> [ScheduleCalendar] { await wrapped.calendars() }
    func changes() async -> AsyncStream<Void> { await wrapped.changes() }
    nonisolated var eventDetails: any EventDetailPresenter { wrapped.eventDetails }
}
