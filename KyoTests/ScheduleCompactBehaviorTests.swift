import XCTest

/// The compact Schedule: the collapsed set, "+N more", expanding, Now / Until, past dimming and the
/// empty states, all driven by a controllable clock through `ScheduleStore`.
@MainActor
final class ScheduleCompactBehaviorTests: XCTestCase {
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
        _ title: String, _ start: Date, until end: Date, calendarTitle: String = "Work", location: String? = nil
    ) -> ScheduleEvent {
        ScheduleEvent(
            id: ScheduleEventID(eventID: title, occurrenceDate: start),
            title: title, start: start, end: end, location: location, calendarTitle: calendarTitle
        )
    }

    private func allDay(_ title: String) -> ScheduleEvent {
        ScheduleEvent(
            id: ScheduleEventID(eventID: title, occurrenceDate: date()),
            title: title, start: date(), end: date(day: 3), isAllDay: true
        )
    }

    private func makeStore(
        _ events: [ScheduleEvent], now: @escaping () -> Date, sleep: ScheduleStore.Sleep? = nil
    ) async -> ScheduleStore {
        let service = FakeCalendarService(events: events)
        let store: ScheduleStore
        if let sleep {
            store = ScheduleStore(service: service, now: now, calendar: calendar, locale: locale, sleep: sleep)
        } else {
            store = ScheduleStore(service: service, now: now, calendar: calendar, locale: locale)
        }
        await store.refresh()
        return store
    }

    private func titles(_ rows: [ScheduleRowPresentation]) -> [String] { rows.map(\.event.title) }

    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// Six timed events across the day, 09:00 to 15:00, one hour each.
    private var sixEvents: [ScheduleEvent] {
        (0..<6).map { index in
            timed("Event \(index + 1)", date(9 + index), until: date(10 + index))
        }
    }

    // MARK: The collapsed set and "+N more"

    func testCollapsedShowsTheFirstThreeUpcomingEventsAndCountsTheRest() async {
        let store = await makeStore(sixEvents, now: { self.date(8) })

        XCTAssertEqual(titles(store.visibleRows), ["Event 1", "Event 2", "Event 3"])
        XCTAssertEqual(store.hiddenCount, 3)
        XCTAssertEqual(store.moreText, "+3 more")
    }

    func testCollapsedSkipsEndedEventsButCountsThemInMore() async {
        // 11:30: events 1 and 2 have ended, 3 is in progress, 4 to 6 are still to come.
        let store = await makeStore(sixEvents, now: { self.date(11, 30) })

        XCTAssertEqual(titles(store.visibleRows), ["Event 3", "Event 4", "Event 5"])
        XCTAssertEqual(store.visibleRows.map(\.state), [.inProgress, .upcoming, .upcoming])
        XCTAssertEqual(store.moreText, "+3 more", "two ended and one more to come")
    }

    func testThereIsNoMoreRowWhenNothingIsHidden() async {
        let store = await makeStore(Array(sixEvents.prefix(3)), now: { self.date(8) })

        XCTAssertEqual(titles(store.visibleRows), ["Event 1", "Event 2", "Event 3"])
        XCTAssertEqual(store.hiddenCount, 0)
        XCTAssertNil(store.moreText)
    }

    func testAnEndedEventAloneIsEnoughForAMoreRow() async {
        let store = await makeStore(Array(sixEvents.prefix(2)), now: { self.date(9, 30) })

        XCTAssertEqual(titles(store.visibleRows), ["Event 1", "Event 2"])
        XCTAssertNil(store.moreText)

        let later = await makeStore(Array(sixEvents.prefix(2)), now: { self.date(10, 30) })
        XCTAssertEqual(titles(later.visibleRows), ["Event 2"])
        XCTAssertEqual(later.moreText, "+1 more")
        XCTAssertEqual(later.moreAccessibilityLabel, "1 more event")
    }

    func testTheAllDayLineIsNeitherInTheThreeNorInTheCount() async {
        let events = [allDay("Holiday"), allDay("Sam's birthday")] + sixEvents
        let store = await makeStore(events, now: { self.date(8) })

        XCTAssertEqual(store.visibleRows.count, 3)
        XCTAssertEqual(store.moreText, "+3 more")
        XCTAssertEqual(store.moreAccessibilityLabel, "3 more events")
        XCTAssertEqual(store.allDayLine, "All day · Holiday, Sam's birthday")

        store.expand()
        XCTAssertEqual(store.visibleRows.count, 6)
        XCTAssertEqual(store.allDayLine, "All day · Holiday, Sam's birthday")
    }

    func testAnAllDayEventAloneHasNoNothingElseTodayAndNoMoreRow() async {
        let store = await makeStore([allDay("Holiday")], now: { self.date(8) })

        XCTAssertTrue(store.visibleRows.isEmpty)
        XCTAssertNil(store.moreText)
        XCTAssertFalse(store.showsNothingElseToday)
        XCTAssertFalse(store.showsNothingScheduled)
    }

    // MARK: Expand and collapse

    func testExpandingShowsEveryEventInTimeOrderWithEndedOnesMarkedPast() async {
        let store = await makeStore(sixEvents, now: { self.date(11, 30) })

        store.expand()

        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(titles(store.visibleRows), (1...6).map { "Event \($0)" })
        XCTAssertEqual(store.visibleRows.map(\.state), [.past, .past, .inProgress, .upcoming, .upcoming, .upcoming])
        XCTAssertNil(store.moreText)
        XCTAssertTrue(store.showsShowLess)
    }

    func testCollapsingReturnsToTheCompactSet() async {
        let store = await makeStore(sixEvents, now: { self.date(8) })
        store.expand()

        store.collapse()

        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(titles(store.visibleRows), ["Event 1", "Event 2", "Event 3"])
        XCTAssertEqual(store.moreText, "+3 more")
        XCTAssertFalse(store.showsShowLess)
    }

    func testAFreshStoreStartsCollapsed() async {
        let store = await makeStore(sixEvents, now: { self.date(8) })

        XCTAssertFalse(store.isExpanded)
    }

    func testExpandingDoesNothingWhenNothingIsHidden() async {
        let store = await makeStore(Array(sixEvents.prefix(2)), now: { self.date(8) })

        store.expand()

        XCTAssertFalse(store.isExpanded)
        XCTAssertFalse(store.showsShowLess)
    }

    func testStaysExpandedAcrossARefreshOnTheSameDay() async {
        let store = await makeStore(sixEvents, now: { self.date(8) })
        store.expand()

        await store.refresh()

        XCTAssertTrue(store.isExpanded)
    }

    func testExpandedStateResetsWhenTodayRollsOver() async {
        var clock = date(23, 30)
        let store = await makeStore(sixEvents, now: { clock })
        store.expand()
        XCTAssertTrue(store.isExpanded)

        clock = date(0, 5, day: 3)
        await store.refresh()

        XCTAssertFalse(store.isExpanded)
    }

    func testItCollapsesOnItsOwnWhenNothingIsLeftToHide() async {
        let service = FakeCalendarService(events: sixEvents)
        let store = ScheduleStore(service: service, now: { self.date(8) }, calendar: calendar, locale: locale)
        await store.refresh()
        store.expand()

        await service.setEvents(Array(sixEvents.prefix(2)))
        await store.refresh()

        XCTAssertFalse(store.isExpanded)
        XCTAssertFalse(store.showsShowLess)
        XCTAssertEqual(store.visibleRows.count, 2)
    }

    // MARK: Now and Until

    func testAnInProgressEventShowsNowInPlaceOfItsStartTime() async throws {
        let store = await makeStore([timed("Design review", date(10), until: date(11))], now: { self.date(10, 30) })

        let row = try XCTUnwrap(store.visibleRows.first)

        XCTAssertEqual(row.state, .inProgress)
        XCTAssertEqual(row.timeText, "Now")
    }

    func testAnEventStartingExactlyNowIsInProgressAndOneEndingExactlyNowHasEnded() async {
        let store = await makeStore(
            [timed("Starting", date(10), until: date(11)), timed("Ending", date(9), until: date(10))],
            now: { self.date(10) }
        )
        store.expand()

        let states = Dictionary(uniqueKeysWithValues: store.visibleRows.map { ($0.event.title, $0.state) })

        XCTAssertEqual(states["Starting"], .inProgress)
        XCTAssertEqual(states["Ending"], .past)
    }

    func testUpcomingAndEndedEventsShowTheirStartTime() async {
        let store = await makeStore(
            [timed("Standup", date(9), until: date(10)), timed("Lunch", date(12, 30), until: date(13, 30))],
            now: { self.date(11) }
        )
        store.expand()

        XCTAssertEqual(store.visibleRows.map { plain($0.timeText) }, ["9:00 AM", "12:30 PM"])
    }

    func testAnEventThatStartedBeforeTodayShowsUntilItsEndOnceEnded() async throws {
        let overnight = timed("Overnight deploy", date(23, 0, day: 1), until: date(1, 30))
        let store = await makeStore([overnight], now: { self.date(8) })
        store.expand()

        let row = try XCTUnwrap(store.allTimedRows.first)

        XCTAssertEqual(row.state, .past)
        XCTAssertEqual(plain(row.timeText), "Until 1:30 AM")
    }

    func testAnEventThatStartedBeforeTodayShowsNowWhileItIsStillRunning() async throws {
        let overnight = timed("Overnight deploy", date(23, 0, day: 1), until: date(1, 30))
        let store = await makeStore([overnight], now: { self.date(1) })

        let row = try XCTUnwrap(store.visibleRows.first)

        XCTAssertEqual(row.state, .inProgress)
        XCTAssertEqual(row.timeText, "Now")
    }

    func testAnEventThatStartedTodayAndEndedKeepsItsStartTime() async throws {
        let store = await makeStore([timed("Standup", date(9), until: date(10))], now: { self.date(12) })

        let row = try XCTUnwrap(store.allTimedRows.first)

        XCTAssertEqual(plain(row.timeText), "9:00 AM")
    }

    func testAnEventThatStartsTodayAndRunsPastMidnightShowsItsStartThenNow() async throws {
        let flight = timed("Flight", date(22), until: date(2, 0, day: 3))

        let before = await makeStore([flight], now: { self.date(20) })
        XCTAssertEqual(plain(try XCTUnwrap(before.visibleRows.first).timeText), "10:00 PM")

        let during = await makeStore([flight], now: { self.date(23) })
        XCTAssertEqual(try XCTUnwrap(during.visibleRows.first).timeText, "Now")
    }

    // MARK: Empty states

    func testNothingScheduledWhenTodayHasNoEvents() async {
        let store = await makeStore([], now: { self.date(8) })

        XCTAssertTrue(store.showsNothingScheduled)
        XCTAssertFalse(store.showsNothingElseToday)
        XCTAssertNil(store.moreText)
    }

    func testNothingElseTodayWhenEveryEventHasEnded() async {
        let store = await makeStore(Array(sixEvents.prefix(2)), now: { self.date(20) })

        XCTAssertTrue(store.showsNothingElseToday)
        XCTAssertFalse(store.showsNothingScheduled)
        XCTAssertTrue(store.visibleRows.isEmpty)
        XCTAssertEqual(store.moreText, "+2 more", "the ended events stay reachable")
    }

    func testNothingElseTodayStillShowsTheAllDayLine() async {
        let store = await makeStore([allDay("Holiday")] + Array(sixEvents.prefix(2)), now: { self.date(20) })

        XCTAssertTrue(store.showsNothingElseToday)
        XCTAssertEqual(store.allDayLine, "All day · Holiday")
        XCTAssertEqual(store.moreText, "+2 more", "the all-day line isn't counted")
    }

    func testExpandingAfterEverythingEndedShowsThePastEvents() async {
        let store = await makeStore(Array(sixEvents.prefix(2)), now: { self.date(20) })

        store.expand()

        XCTAssertFalse(store.showsNothingElseToday)
        XCTAssertEqual(titles(store.visibleRows), ["Event 1", "Event 2"])
        XCTAssertEqual(store.visibleRows.map(\.state), [.past, .past])
    }

    func testNothingElseTodayIsGoneWhileAnEventIsStillRunning() async {
        let store = await makeStore(Array(sixEvents.prefix(2)), now: { self.date(10, 30) })

        XCTAssertFalse(store.showsNothingElseToday)
    }

    // MARK: Rows

    func testRowsReadNowOrEndedForVoiceOver() async {
        let store = await makeStore(sixEvents, now: { self.date(10, 30) })
        store.expand()

        let labels = store.visibleRows.map { plain($0.accessibilityLabel) }

        XCTAssertEqual(labels[0], "9:00 AM, Event 1, Work calendar, ended")
        XCTAssertEqual(labels[1], "Now, Event 2, Work calendar")
        XCTAssertEqual(labels[2], "11:00 AM, Event 3, Work calendar")
    }

    func testAnEndedEventThatStartedBeforeTodayReadsUntilAndEnded() async throws {
        let overnight = timed("Overnight deploy", date(23, 0, day: 1), until: date(1, 30))
        let store = await makeStore([overnight], now: { self.date(8) })

        let row = try XCTUnwrap(store.allTimedRows.first)

        XCTAssertEqual(plain(row.accessibilityLabel), "Until 1:30 AM, Overnight deploy, Work calendar, ended")
    }

    func testTheLocationIsTrimmedAndLeftOutWhenBlank() async {
        let store = await makeStore(
            [
                timed("Offsite", date(9), until: date(10), location: "  Room 4  "),
                timed("Call", date(11), until: date(12), location: "   "),
                timed("Walk", date(13), until: date(14)),
            ],
            now: { self.date(8) }
        )

        XCTAssertEqual(store.visibleRows.map(\.location), ["Room 4", nil, nil])
    }

    // MARK: Updating as events start and end

    func testPresentationFollowsTheClockWithoutReadingEventsAgain() async {
        var clock = date(8, 30)
        let service = FakeCalendarService(events: sixEvents)
        let store = ScheduleStore(service: service, now: { clock }, calendar: calendar, locale: locale)
        await store.refresh()
        XCTAssertEqual(titles(store.visibleRows), ["Event 1", "Event 2", "Event 3"])
        let readsBefore = await service.fetchedRanges.count

        clock = date(10, 15)
        store.updateClock()

        XCTAssertEqual(titles(store.visibleRows), ["Event 2", "Event 3", "Event 4"])
        XCTAssertEqual(store.visibleRows.first?.timeText, "Now")
        XCTAssertEqual(store.moreText, "+3 more")
        let readsAfter = await service.fetchedRanges.count
        XCTAssertEqual(readsAfter, readsBefore)
    }

    func testTheNextBoundaryIsTheNextStartOrEndWithinToday() async {
        let events = [
            timed("Standup", date(9), until: date(10)),
            timed("Overnight", date(22), until: date(2, 0, day: 3)),
        ]
        let store = await makeStore(events, now: { self.date(8) })
        XCTAssertEqual(store.nextEventBoundary, date(9))

        let running = await makeStore(events, now: { self.date(9, 30) })
        XCTAssertEqual(running.nextEventBoundary, date(10))

        let evening = await makeStore(events, now: { self.date(22, 30) })
        XCTAssertNil(evening.nextEventBoundary, "an end after midnight is the day-boundary loop's business")
    }

    func testTheBoundaryLoopSleepsUntilEachStartAndEndAndUpdatesTheSet() async {
        var clock = date(8, 30)
        let sleeps = BoundarySleepRecorder()
        let store = await makeStore(
            [timed("Standup", date(9), until: date(9, 30)), timed("Review", date(10), until: date(11))],
            now: { clock },
            sleep: { seconds in try await sleeps.sleep(seconds) }
        )
        XCTAssertEqual(store.visibleRows.map(\.state), [.upcoming, .upcoming])

        let loop = Task { await store.advanceAtEventBoundaries() }
        defer { loop.cancel() }

        await eventually("the first sleep") { sleeps.durations.count == 1 }
        XCTAssertEqual(sleeps.durations, [30 * 60], "until Standup starts")

        clock = date(9)
        sleeps.wake()
        await eventually("Standup to be Now") { store.visibleRows.first?.timeText == "Now" }
        XCTAssertEqual(sleeps.durations.last, 30 * 60, "until Standup ends")

        clock = date(9, 30)
        sleeps.wake()
        await eventually("Standup to drop out") { store.visibleRows.map(\.event.title) == ["Review"] }
        XCTAssertEqual(store.moreText, "+1 more")
        XCTAssertEqual(sleeps.durations.last, 30 * 60, "until Review starts")

        clock = date(10)
        sleeps.wake()
        await eventually("Review to be Now") { store.visibleRows.first?.timeText == "Now" }

        clock = date(11)
        sleeps.wake()
        await eventually("everything to have ended") { store.showsNothingElseToday }
        await loop.value
        XCTAssertEqual(sleeps.durations.count, 4, "it stops once nothing else starts or ends today")
    }

    func testTheBoundaryLoopEndsWhenNothingIsLeftToday() async {
        let sleeps = BoundarySleepRecorder()
        let store = await makeStore(
            [timed("Standup", date(9), until: date(10))], now: { self.date(12) },
            sleep: { seconds in try await sleeps.sleep(seconds) }
        )

        await store.advanceAtEventBoundaries()

        XCTAssertTrue(sleeps.durations.isEmpty)
    }

    /// Polls until `condition` holds, since the loop runs on its own task.
    private func eventually(_ message: String, _ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(message)")
    }
}

/// Stands in for `Task.sleep`: records each requested duration and waits until the test wakes it.
@MainActor
private final class BoundarySleepRecorder {
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
