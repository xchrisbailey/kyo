import UIKit
import XCTest

/// Which palette the app shows: System until a pick, a pick kept in the injected `UserDefaults`, and
/// System again for a stored value that names no current palette preference.
@MainActor
final class PalettePreferenceBehaviorTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
        suiteNames = []
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        let name = "kyo.palettePreference.tests.\(UUID().uuidString)"
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    func testThePreferenceIsSystemWhenNothingIsStored() {
        let store = PalettePreferenceStore(defaults: makeDefaults())

        XCTAssertEqual(store.current, .system)
    }

    func testAPickAppliesAtOnce() {
        let store = PalettePreferenceStore(defaults: makeDefaults())

        store.select(.dark)

        XCTAssertEqual(store.current, .dark)
    }

    func testEveryPickIsReadBackByANewStoreOnTheSameDefaults() {
        for preference in PalettePreference.allCases {
            let defaults = makeDefaults()
            PalettePreferenceStore(defaults: defaults).select(preference)

            XCTAssertEqual(PalettePreferenceStore(defaults: defaults).current, preference)
        }
    }

    func testPickingSystemAgainIsReadBackToo() {
        let defaults = makeDefaults()
        let store = PalettePreferenceStore(defaults: defaults)
        store.select(.light)
        store.select(.system)

        XCTAssertEqual(PalettePreferenceStore(defaults: defaults).current, .system)
    }

    func testAStoredValueNamingNoCurrentPreferenceGivesSystem() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: PalettePreferenceStore.storageKey)

        XCTAssertEqual(PalettePreferenceStore(defaults: defaults).current, .system)
    }

    func testAStoredValueOfTheWrongTypeGivesSystem() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: PalettePreferenceStore.storageKey)

        XCTAssertEqual(PalettePreferenceStore(defaults: defaults).current, .system)
    }

    func testThePreferenceIsKeptApartFromTheTheme() {
        let defaults = makeDefaults()
        let preferences = PalettePreferenceStore(defaults: defaults)
        let themes = ThemeStore(defaults: defaults)
        preferences.select(.dark)

        themes.select(.neko)

        XCTAssertEqual(preferences.current, .dark, "switching themes leaves the preference alone")
        XCTAssertEqual(PalettePreferenceStore(defaults: defaults).current, .dark)
        XCTAssertEqual(ThemeStore(defaults: defaults).current.id, Theme.neko.id)
    }

    func testTheSegmentsAreSystemLightDarkInThatOrder() {
        XCTAssertEqual(PalettePreference.allCases.map(\.name), ["System", "Light", "Dark"])
    }

    func testSystemLeavesTheWindowsToTheDeviceAndTheOthersFixThem() {
        XCTAssertEqual(PalettePreference.system.userInterfaceStyle, .unspecified)
        XCTAssertEqual(PalettePreference.light.userInterfaceStyle, .light)
        XCTAssertEqual(PalettePreference.dark.userInterfaceStyle, .dark)
    }
}
