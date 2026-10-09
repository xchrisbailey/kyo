import XCTest

/// Which theme the Apple Watch wears: Kyo until the phone sends one, the last id it sent kept in
/// the injected `UserDefaults`, Kyo again for an id the Watch has no palette for (the id stays
/// stored), and unchanged by a context that carries no id.
@MainActor
final class WatchThemeBehaviorTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
        suiteNames = []
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        let name = "kyo.watch-theme.tests.\(UUID().uuidString)"
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    func testTheWatchStartsInTheKyoThemeWhenNothingWasReceived() {
        let model = WatchThemeModel(defaults: makeDefaults())

        XCTAssertEqual(model.palette.themeID, "kyo")
    }

    func testTheWatchAdoptsAReceivedThemeAtOnce() {
        let model = WatchThemeModel(defaults: makeDefaults())

        model.receive(themeID: "neko")

        XCTAssertEqual(model.palette.themeID, "neko")
    }

    func testANewModelOnTheSameDefaultsReadsTheReceivedThemeBack() {
        let defaults = makeDefaults()
        WatchThemeModel(defaults: defaults).receive(themeID: "techo")

        XCTAssertEqual(WatchThemeModel(defaults: defaults).palette.themeID, "techo")
    }

    func testAnIdTheWatchHasNoPaletteForShowsKyoAndStaysStored() {
        let defaults = makeDefaults()
        let model = WatchThemeModel(defaults: defaults)
        model.receive(themeID: "neko")

        model.receive(themeID: "a-theme-from-a-newer-phone")

        XCTAssertEqual(model.palette.themeID, "kyo")
        XCTAssertEqual(defaults.string(forKey: WatchThemeModel.storageKey), "a-theme-from-a-newer-phone")
        XCTAssertEqual(WatchThemeModel(defaults: defaults).palette.themeID, "kyo")
    }

    func testALaterKnownIdReplacesAnUnknownOne() {
        let defaults = makeDefaults()
        let model = WatchThemeModel(defaults: defaults)
        model.receive(themeID: "a-theme-from-a-newer-phone")

        model.receive(themeID: "techo")

        XCTAssertEqual(model.palette.themeID, "techo")
        XCTAssertEqual(WatchThemeModel(defaults: defaults).palette.themeID, "techo")
    }

    func testAStoredIdTheWatchHasNoPaletteForShowsKyoWithoutRewritingIt() {
        let defaults = makeDefaults()
        defaults.set("a-theme-from-a-newer-phone", forKey: WatchThemeModel.storageKey)

        let model = WatchThemeModel(defaults: defaults)

        XCTAssertEqual(model.palette.themeID, "kyo")
        XCTAssertEqual(defaults.string(forKey: WatchThemeModel.storageKey), "a-theme-from-a-newer-phone")
    }

    func testAStoredValueOfTheWrongTypeShowsKyo() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: WatchThemeModel.storageKey)

        XCTAssertEqual(WatchThemeModel(defaults: defaults).palette.themeID, "kyo")
    }

    // MARK: Arrival

    func testATransportDeliveryAfterTheModelExistsChangesTheTheme() {
        let transport = ControllableThemeTransport()
        let model = WatchThemeModel(defaults: makeDefaults(), transport: transport)

        transport.deliver("neko")

        XCTAssertEqual(model.palette.themeID, "neko")
    }

    func testAnIdThatArrivedBeforeTheModelExistedIsAppliedWhenItRegisters() {
        let transport = ControllableThemeTransport()
        transport.deliver("techo")

        let model = WatchThemeModel(defaults: makeDefaults(), transport: transport)

        XCTAssertEqual(model.palette.themeID, "techo")
    }

    func testTheModelNeverPublishesAThemeToTheTransport() {
        let transport = ControllableThemeTransport()
        let model = WatchThemeModel(defaults: makeDefaults(), transport: transport)

        transport.deliver("neko")
        model.receive(themeID: "techo")

        XCTAssertTrue(transport.published.isEmpty)
    }
}
