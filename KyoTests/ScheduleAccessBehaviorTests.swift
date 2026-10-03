import UIKit
import XCTest

/// What the Schedule section shows for each authorization state, and the Show schedule switch.
@MainActor
final class ScheduleAccessBehaviorTests: XCTestCase {
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

    private func standup() -> ScheduleEvent {
        ScheduleEvent(
            id: ScheduleEventID(eventID: "standup", occurrenceDate: date(9)),
            title: "Standup", start: date(9), end: date(10)
        )
    }

    /// A private defaults domain, so a test never touches the device's real settings.
    private func makeDefaults() -> UserDefaults {
        let suite = "kyo.tests.schedule.\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func makeStore(
        _ service: FakeCalendarService, defaults: UserDefaults? = nil, openSettings: @escaping @MainActor () -> Void = {}
    ) -> ScheduleStore {
        ScheduleStore(
            service: service, now: { self.date(8) }, calendar: calendar, locale: Locale(identifier: "en_US"),
            defaults: defaults ?? makeDefaults(), openSettings: openSettings
        )
    }

    private func eventually(_ message: String, _ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(message)")
    }

    // MARK: Every authorization state

    func testNotDeterminedShowsOnlyTheConnectLine() async {
        let store = makeStore(FakeCalendarService(access: .notDetermined, events: [standup()]))
        await store.refresh()

        XCTAssertTrue(store.showsSection)
        XCTAssertTrue(store.showsConnectPrompt)
        XCTAssertFalse(store.showsAccessOffLine)
        XCTAssertFalse(store.showsUnavailableLine)
        XCTAssertFalse(store.showsEvents)
    }

    func testFullAccessShowsEventsAndNoPromptLine() async {
        let store = makeStore(FakeCalendarService(access: .fullAccess, events: [standup()]))
        await store.refresh()

        XCTAssertTrue(store.showsSection)
        XCTAssertTrue(store.showsEvents)
        XCTAssertFalse(store.showsConnectPrompt)
        XCTAssertFalse(store.showsAccessOffLine)
        XCTAssertFalse(store.showsUnavailableLine)
    }

    func testDeniedAndWriteOnlyAccessShowTheAccessOffLine() async {
        // `.writeOnly` also stands for the deprecated `.authorized`: neither can read events.
        for access in [CalendarAccess.denied, .writeOnly] {
            let service = FakeCalendarService(access: access, events: [standup()])
            let store = makeStore(service)
            await store.refresh()

            XCTAssertTrue(store.showsSection, "\(access)")
            XCTAssertTrue(store.showsAccessOffLine, "\(access)")
            XCTAssertFalse(store.showsConnectPrompt, "\(access)")
            XCTAssertFalse(store.showsUnavailableLine, "\(access)")
            XCTAssertFalse(store.showsEvents, "\(access)")
            XCTAssertTrue(store.events.isEmpty, "\(access)")
            let fetched = await service.fetchedRanges
            XCTAssertTrue(fetched.isEmpty, "\(access)")
        }
    }

    func testRestrictedAccessShowsTheUnavailableLine() async {
        let store = makeStore(FakeCalendarService(access: .restricted, events: [standup()]))
        await store.refresh()

        XCTAssertTrue(store.showsSection)
        XCTAssertTrue(store.showsUnavailableLine)
        XCTAssertFalse(store.showsAccessOffLine)
        XCTAssertFalse(store.showsConnectPrompt)
        XCTAssertFalse(store.showsEvents)
    }

    func testReturningFromSettingsWithAccessGrantedShowsEvents() async {
        let service = FakeCalendarService(access: .denied, events: [standup()])
        let store = makeStore(service)
        await store.refresh()
        XCTAssertTrue(store.showsAccessOffLine)

        await service.setAccess(.fullAccess)
        await store.refresh()

        XCTAssertFalse(store.showsAccessOffLine)
        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup"])
    }

    // MARK: Open Settings

    func testOpenSettingsOpensTheAppSettingsPage() {
        var opened = 0
        let store = makeStore(FakeCalendarService(access: .denied)) { opened += 1 }

        store.openSettings()

        XCTAssertEqual(opened, 1)
        XCTAssertEqual(store.settingsOpenRequests, 1)
        XCTAssertNotNil(URL(string: UIApplication.openSettingsURLString))
    }

    // MARK: Show schedule

    func testShowScheduleIsOnByDefault() {
        let store = makeStore(FakeCalendarService())

        XCTAssertTrue(store.showsSchedule)
    }

    func testDismissingAnyPromptLineTurnsShowScheduleOffAndHidesTheSection() async {
        for access in [CalendarAccess.notDetermined, .denied, .writeOnly, .restricted] {
            let store = makeStore(FakeCalendarService(access: access))
            await store.refresh()
            XCTAssertTrue(store.showsSection, "\(access)")

            store.dismissSchedule()

            XCTAssertFalse(store.showsSchedule, "\(access)")
            XCTAssertFalse(store.showsSection, "\(access)")
            XCTAssertFalse(store.showsConnectPrompt, "\(access)")
            XCTAssertFalse(store.showsAccessOffLine, "\(access)")
            XCTAssertFalse(store.showsUnavailableLine, "\(access)")
        }
    }

    func testTurningShowScheduleOffHidesEventsAndStopsFetching() async {
        let service = FakeCalendarService(access: .fullAccess, events: [standup()])
        let store = makeStore(service)
        await store.refresh()
        XCTAssertTrue(store.showsEvents)
        let fetchesBefore = await service.fetchedRanges.count

        store.setShowsSchedule(false)
        await store.refresh()
        await store.connect()
        await service.emitChange()

        XCTAssertFalse(store.showsSection)
        XCTAssertFalse(store.showsEvents)
        XCTAssertTrue(store.events.isEmpty)
        let fetchesAfter = await service.fetchedRanges.count
        XCTAssertEqual(fetchesAfter, fetchesBefore, "no events are fetched while Show schedule is off")
    }

    func testTurningShowScheduleBackOnShowsTheCurrentAccessState() async {
        let service = FakeCalendarService(access: .notDetermined, events: [standup()])
        let store = makeStore(service)
        await store.refresh()
        store.dismissSchedule()
        // Access changes in Settings while the section is hidden.
        await service.setAccess(.denied)

        store.setShowsSchedule(true)

        await eventually("the access off line") { store.showsAccessOffLine }
        XCTAssertTrue(store.showsSchedule)
        XCTAssertFalse(store.showsConnectPrompt)
    }

    func testTurningShowScheduleBackOnShowsEventsWhenAccessIsFull() async {
        let service = FakeCalendarService(access: .fullAccess, events: [standup()])
        let store = makeStore(service)
        await store.refresh()
        store.setShowsSchedule(false)

        store.setShowsSchedule(true)

        await eventually("events") { store.showsEvents }
        XCTAssertEqual(store.timedEvents.map(\.title), ["Standup"])
    }

    func testAReadStartedBeforeTurningShowScheduleOffDoesNotShowAfterwards() async {
        let service = FakeCalendarService(access: .fullAccess, events: [standup()])
        let store = makeStore(service)
        let read = Task { await store.refresh() }
        await Task.yield()

        store.setShowsSchedule(false)
        await read.value

        XCTAssertFalse(store.showsSection)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testShowScheduleIsRememberedOnThisDevice() async {
        let defaults = makeDefaults()
        let first = makeStore(FakeCalendarService(access: .denied), defaults: defaults)
        first.setShowsSchedule(false)
        XCTAssertEqual(defaults.object(forKey: ScheduleStore.showsScheduleKey) as? Bool, false)

        let relaunched = makeStore(FakeCalendarService(access: .denied), defaults: defaults)
        XCTAssertFalse(relaunched.showsSchedule)
        await relaunched.refresh()
        XCTAssertFalse(relaunched.showsSection)

        relaunched.setShowsSchedule(true)
        let again = makeStore(FakeCalendarService(access: .denied), defaults: defaults)
        XCTAssertTrue(again.showsSchedule)
    }
}
