import XCTest

/// Which theme the app wears: Kyo until a pick, a pick kept in the injected `UserDefaults`, and Kyo
/// again for a stored value that names no current theme.
@MainActor
final class ThemeChoiceBehaviorTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
        suiteNames = []
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        let name = "kyo.theme.tests.\(UUID().uuidString)"
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    func testTheThemeIsKyoWhenNothingIsStored() {
        let store = ThemeStore(defaults: makeDefaults())

        XCTAssertEqual(store.current.id, Theme.kyo.id)
    }

    func testAPickAppliesAtOnce() {
        let store = ThemeStore(defaults: makeDefaults())

        store.select(.neko)

        XCTAssertEqual(store.current.id, Theme.neko.id)
    }

    func testAPickIsReadBackByANewStoreOnTheSameDefaults() {
        let defaults = makeDefaults()
        ThemeStore(defaults: defaults).select(.neko)

        XCTAssertEqual(ThemeStore(defaults: defaults).current.id, Theme.neko.id)
    }

    func testPickingKyoAgainIsReadBackToo() {
        let defaults = makeDefaults()
        let store = ThemeStore(defaults: defaults)
        store.select(.neko)
        store.select(.kyo)

        XCTAssertEqual(ThemeStore(defaults: defaults).current.id, Theme.kyo.id)
    }

    func testAStoredValueNamingNoCurrentThemeGivesKyo() {
        let defaults = makeDefaults()
        defaults.set("a-theme-that-was-removed", forKey: ThemeStore.storageKey)

        XCTAssertEqual(ThemeStore(defaults: defaults).current.id, Theme.kyo.id)
    }

    func testAStoredValueOfTheWrongTypeGivesKyo() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: ThemeStore.storageKey)

        XCTAssertEqual(ThemeStore(defaults: defaults).current.id, Theme.kyo.id)
    }

    func testEveryThemeHasItsOwnName() {
        XCTAssertEqual(Set(Theme.all.map(\.id)).count, Theme.all.count)
    }

    func testEveryThemeIsFoundByItsId() {
        for theme in Theme.all {
            XCTAssertEqual(Theme.named(theme.id)?.id, theme.id)
        }
    }
}
