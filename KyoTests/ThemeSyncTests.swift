import Combine
import WatchConnectivity
import XCTest

/// The theme id on its way from the phone to the Watch (ADR 0007): through the transport's one
/// publish path, in the same context write as the three snapshots, and out again on the Watch side
/// by both paths a context arrives by. The transport here has no session, so nothing is sent; the
/// context it would write is what's read.
@MainActor
final class ThemeSyncTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
        suiteNames = []
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        let name = "kyo.theme-sync.tests.\(UUID().uuidString)"
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func id(in context: [String: Any]) -> String? {
        (context[WatchConnectivityTaskTransport.themeIDKey] as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func publishAllSnapshots(_ transport: WatchConnectivityTaskTransport) {
        transport.publish(TaskListSnapshot(revision: 1, tasks: []))
        transport.publish(HabitListSnapshot(revision: 1, habits: []))
        transport.publish(MemoListSnapshot(revision: 1, memos: []))
    }

    // MARK: Phone: the published context

    func testTheContextCarriesTheThemeIdWithAllThreeSnapshotsStillInIt() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        publishAllSnapshots(transport)

        transport.publish(themeID: "neko")

        let context = transport.contextToWrite ?? [:]
        XCTAssertEqual(id(in: context), "neko")
        XCTAssertNotNil(context[WatchConnectivityTaskTransport.snapshotKey])
        XCTAssertNotNil(context[WatchConnectivityTaskTransport.habitSnapshotKey])
        XCTAssertNotNil(context[WatchConnectivityTaskTransport.memoSnapshotKey])
        XCTAssertEqual(context.count, 4)
    }

    func testPublishingASnapshotKeepsTheThemeId() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        transport.publish(themeID: "techo")

        publishAllSnapshots(transport)
        transport.publish(TaskListSnapshot(revision: 2, tasks: []))

        XCTAssertEqual(id(in: transport.contextToWrite ?? [:]), "techo")
        XCTAssertEqual(transport.contextToWrite?.count, 4)
    }

    func testANewerThemeIdReplacesTheOldOneAndKeepsTheSnapshots() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        publishAllSnapshots(transport)
        transport.publish(themeID: "neko")

        transport.publish(themeID: "techo")

        XCTAssertEqual(id(in: transport.contextToWrite ?? [:]), "techo")
        XCTAssertEqual(transport.contextToWrite?.count, 4)
    }

    func testAThemeIdAloneNeverCausesTheFirstWriteOfALaunch() {
        let transport = WatchConnectivityTaskTransport(session: nil)

        transport.publish(themeID: "neko")

        XCTAssertNil(transport.contextToWrite)
    }

    func testTheFirstSnapshotOfALaunchWritesTheThemeIdAlongWithIt() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        transport.publish(themeID: "neko")

        transport.publish(TaskListSnapshot(revision: 1, tasks: []))

        let context = transport.contextToWrite ?? [:]
        XCTAssertEqual(id(in: context), "neko")
        XCTAssertNotNil(context[WatchConnectivityTaskTransport.snapshotKey])
    }

    func testAThemeChangeAfterASnapshotWritesAtOnceWithEverySnapshot() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        transport.publish(TaskListSnapshot(revision: 1, tasks: []))
        XCTAssertEqual(transport.contextToWrite?.count, 1)

        transport.publish(themeID: "techo")

        let context = transport.contextToWrite ?? [:]
        XCTAssertEqual(id(in: context), "techo")
        XCTAssertNotNil(context[WatchConnectivityTaskTransport.snapshotKey])
    }

    func testTheThemeIdTravelsUnderItsOwnKey() {
        XCTAssertEqual(WatchConnectivityTaskTransport.themeIDKey, "kyo.themeID")
    }

    // MARK: Phone: the store

    func testAPhoneAlreadyOnNekoPublishesItsThemeWhenItStarts() {
        let defaults = makeDefaults()
        defaults.set("neko", forKey: ThemeStore.storageKey)
        let transport = ControllableThemeTransport()

        _ = ThemeStore(defaults: defaults, transport: transport)

        XCTAssertEqual(transport.published, ["neko"])
    }

    func testAPhoneOnTheKyoThemePublishesItWhenItStarts() {
        let transport = ControllableThemeTransport()

        _ = ThemeStore(defaults: makeDefaults(), transport: transport)

        XCTAssertEqual(transport.published, ["kyo"])
    }

    func testAChangeOfThemePublishesTheNewId() {
        let transport = ControllableThemeTransport()
        let store = ThemeStore(defaults: makeDefaults(), transport: transport)

        store.select(.techo)
        store.select(.neko)

        XCTAssertEqual(transport.published, ["kyo", "techo", "neko"])
    }

    func testAStoreWithNoTransportPublishesNothingAndStillWorks() {
        let store = ThemeStore(defaults: makeDefaults())

        store.select(.neko)

        XCTAssertEqual(store.current.id, "neko")
    }

    func testAnInMemoryLaunchPublishesNothingAndNeverAsksForTheTransport() {
        let store = ThemeSelection.make(
            environment: [KyoModelContainer.inMemoryEnvironmentKey: "1"], transport: failingTransportRequest
        )

        store.select(.neko)

        XCTAssertEqual(store.current.id, "neko")
    }

    func testALaunchWithAThemeSuitePublishesNothingAndNeverAsksForTheTransport() {
        let store = ThemeSelection.make(
            environment: [ThemeSelection.suiteEnvironmentKey: "kyo.theme.tests.\(UUID().uuidString)"],
            transport: failingTransportRequest
        )

        store.select(.neko)

        XCTAssertEqual(store.current.id, "neko")
    }

    func testARealLaunchPublishesItsThemeWhenItStarts() {
        let transport = ControllableThemeTransport()

        let store = ThemeSelection.make(environment: [:], defaults: makeDefaults(), transport: { transport })

        XCTAssertEqual(transport.published, [store.current.id])
    }

    /// A launch that must not touch the live transport fails the test if it asks for any.
    private func failingTransportRequest() -> any ThemeIDTransport {
        XCTFail("this launch asked for the transport")
        return ControllableThemeTransport()
    }

    // MARK: Watch: which launches follow the phone

    func testALaunchWithAWatchThemeSuiteTakesNoFeedFromThePhoneAndWritesOnlyToTheSuite() {
        let suite = "kyo.watch-theme.tests.\(UUID().uuidString)"
        suiteNames.append(suite)
        UserDefaults(suiteName: suite)!.set("techo", forKey: WatchThemeStore.storageKey)

        let model = WatchThemeSelection.make(
            environment: [WatchThemeSelection.suiteEnvironmentKey: suite], transport: failingTransportRequest
        )

        XCTAssertEqual(model.palette.themeID, "techo")
        model.receive(themeID: "neko")
        XCTAssertEqual(UserDefaults(suiteName: suite)!.string(forKey: WatchThemeStore.storageKey), "neko")
    }

    func testAnInMemoryWatchLaunchStartsInKyoWithNoFeedFromThePhone() {
        let model = WatchThemeSelection.make(
            environment: [KyoModelContainer.inMemoryEnvironmentKey: "1"], transport: failingTransportRequest
        )

        XCTAssertEqual(model.palette.themeID, "kyo")
    }

    func testARealWatchLaunchFollowsThePhone() {
        let transport = ControllableThemeTransport()
        let model = WatchThemeSelection.make(environment: [:], defaults: makeDefaults(), transport: { transport })

        transport.deliver("neko")

        XCTAssertEqual(model.palette.themeID, "neko")
    }

    // MARK: Watch: both paths a context arrives by

    private func receivedIDs(_ transport: WatchConnectivityTaskTransport) -> ReceivedIDs {
        let received = ReceivedIDs()
        transport.setThemeIDHandler { received.ids.append($0) }
        return received
    }

    private final class ReceivedIDs {
        var ids: [String] = []
    }

    func testAContextArrivingWhileTheAppRunsDeliversItsThemeId() async {
        let transport = WatchConnectivityTaskTransport(session: nil)
        let received = ReceivedIDs()
        let delivered = expectation(description: "theme id delivered")
        transport.setThemeIDHandler { id in received.ids.append(id); delivered.fulfill() }

        transport.session(WCSession.default, didReceiveApplicationContext: [
            WatchConnectivityTaskTransport.themeIDKey: Data("techo".utf8),
        ])
        await fulfillment(of: [delivered], timeout: 5)

        XCTAssertEqual(received.ids, ["techo"])
    }

    /// Activation reads the session's waiting context (not reachable without a real session) and hands
    /// it to `handleActivation`, which these tests call.
    func testAContextWaitingAtLaunchDeliversItsThemeIdWhenTheSessionActivates() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        let received = receivedIDs(transport)

        transport.handleActivation(receivedContext: .init([WatchConnectivityTaskTransport.themeIDKey: Data("neko".utf8)]))

        XCTAssertEqual(received.ids, ["neko"])
    }

    func testAContextWaitingAtLaunchWithNoThemeIdLeavesAnEarlierOneAlone() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        transport.handleActivation(receivedContext: .init([WatchConnectivityTaskTransport.themeIDKey: Data("neko".utf8)]))
        transport.handleActivation(receivedContext: .init([WatchConnectivityTaskTransport.snapshotKey: Data()]))

        let received = receivedIDs(transport)

        XCTAssertEqual(received.ids, ["neko"])
    }

    func testAContextWithNoThemeIdDeliversNothing() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        let received = receivedIDs(transport)

        transport.receive(WatchConnectivityTaskTransport.ReceivedContext([WatchConnectivityTaskTransport.snapshotKey: Data()]))

        XCTAssertTrue(received.ids.isEmpty)
    }

    func testAnUnreadableThemeIdDeliversNothing() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        let received = receivedIDs(transport)

        transport.receive(WatchConnectivityTaskTransport.ReceivedContext([WatchConnectivityTaskTransport.themeIDKey: Data([0xff, 0xfe])]))
        transport.receive(WatchConnectivityTaskTransport.ReceivedContext([WatchConnectivityTaskTransport.themeIDKey: Data()]))
        transport.receive(WatchConnectivityTaskTransport.ReceivedContext([WatchConnectivityTaskTransport.themeIDKey: "neko"]))

        XCTAssertTrue(received.ids.isEmpty)
    }

    func testAnIdThatArrivedBeforeAReceiverRegisteredIsHandedOverWhenItDoes() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        transport.handleActivation(receivedContext: .init([WatchConnectivityTaskTransport.themeIDKey: Data("neko".utf8)]))

        let received = receivedIDs(transport)

        XCTAssertEqual(received.ids, ["neko"])
    }

    func testAContextWithNoThemeIdLeavesTheWatchsStoredThemeAlone() {
        let transport = WatchConnectivityTaskTransport(session: nil)
        let model = WatchThemeStore(defaults: makeDefaults(), transport: transport)
        transport.receive(WatchConnectivityTaskTransport.ReceivedContext([WatchConnectivityTaskTransport.themeIDKey: Data("neko".utf8)]))

        transport.receive(WatchConnectivityTaskTransport.ReceivedContext([WatchConnectivityTaskTransport.snapshotKey: Data()]))

        XCTAssertEqual(model.palette.themeID, "neko")
    }

    func testAWatchThemeStoreFollowsTheRealTransportOnBothPaths() async {
        let transport = WatchConnectivityTaskTransport(session: nil)
        let model = WatchThemeStore(defaults: makeDefaults(), transport: transport)

        transport.receive(WatchConnectivityTaskTransport.ReceivedContext([WatchConnectivityTaskTransport.themeIDKey: Data("neko".utf8)]))
        XCTAssertEqual(model.palette.themeID, "neko")

        let changed = expectation(description: "palette changed")
        let observation = model.$palette.dropFirst().sink { _ in changed.fulfill() }
        transport.session(WCSession.default, didReceiveApplicationContext: [
            WatchConnectivityTaskTransport.themeIDKey: Data("techo".utf8),
        ])
        await fulfillment(of: [changed], timeout: 5)
        observation.cancel()

        XCTAssertEqual(model.palette.themeID, "techo")
    }
}
