import XCTest

/// The Apple Watch's palette: a fixed color value can be built and read back, and palettes are keyed by their theme id.
final class WatchPaletteTests: XCTestCase {
    private func fixed(_ value: Double) -> WatchPaletteColor {
        .fixed(red: value, green: value / 2, blue: value / 4, opacity: 1)
    }

    func testAPaletteOfFixedColorsReadsEachRoleBack() {
        let palette = WatchPalette(
            themeID: "test",
            card: .fixed(red: 0.2, green: 0.3, blue: 0.4, opacity: 0.72),
            listRow: fixed(0.4),
            divider: fixed(0.5),
            accent: fixed(0.6),
            primaryText: fixed(0.7),
            secondaryText: fixed(0.8),
            tertiaryText: fixed(0.85),
            warning: fixed(0.9),
            destructive: fixed(1.0),
            editTint: fixed(0.3),
            onAccent: fixed(0.1),
            onWarning: fixed(0.15),
            onDestructive: fixed(0.25)
        )

        XCTAssertEqual(palette.themeID, "test")
        XCTAssertEqual(palette.card.components, .init(red: 0.2, green: 0.3, blue: 0.4, opacity: 0.72))
        XCTAssertEqual(palette.listRow.components, .init(red: 0.4, green: 0.2, blue: 0.1, opacity: 1))
        XCTAssertEqual(palette.divider.components, .init(red: 0.5, green: 0.25, blue: 0.125, opacity: 1))
        XCTAssertEqual(palette.accent.components, .init(red: 0.6, green: 0.3, blue: 0.15, opacity: 1))
        XCTAssertEqual(palette.primaryText.components, .init(red: 0.7, green: 0.35, blue: 0.175, opacity: 1))
        XCTAssertEqual(palette.secondaryText.components, .init(red: 0.8, green: 0.4, blue: 0.2, opacity: 1))
        XCTAssertEqual(palette.tertiaryText.components, .init(red: 0.85, green: 0.425, blue: 0.2125, opacity: 1))
        XCTAssertEqual(palette.warning.components, .init(red: 0.9, green: 0.45, blue: 0.225, opacity: 1))
        XCTAssertEqual(palette.destructive.components, .init(red: 1.0, green: 0.5, blue: 0.25, opacity: 1))
        XCTAssertEqual(palette.editTint.components, .init(red: 0.3, green: 0.15, blue: 0.075, opacity: 1))
        XCTAssertEqual(palette.onAccent?.components, .init(red: 0.1, green: 0.05, blue: 0.025, opacity: 1))
        XCTAssertEqual(palette.onWarning?.components, .init(red: 0.15, green: 0.075, blue: 0.0375, opacity: 1))
        XCTAssertEqual(palette.onDestructive?.components, .init(red: 0.25, green: 0.125, blue: 0.0625, opacity: 1))
    }

    func testAButtonLabelRoleCanBeLeftToWatchOS() {
        let palette = WatchPalette(
            themeID: "test",
            card: fixed(0.1), listRow: fixed(0.1), divider: fixed(0.1), accent: fixed(0.1),
            primaryText: fixed(0.1), secondaryText: fixed(0.1), tertiaryText: fixed(0.1), warning: fixed(0.1),
            destructive: fixed(0.1), editTint: fixed(0.1),
            onAccent: nil, onWarning: nil, onDestructive: nil
        )

        XCTAssertNil(palette.onAccent)
        XCTAssertNil(palette.onWarning)
        XCTAssertNil(palette.onDestructive)
    }

    func testAWatchOSSystemColorHasNoComponentsToRead() {
        XCTAssertNil(WatchPaletteColor.system(.green).components)
    }

    func testEachThemeIsFoundByItsThemeID() {
        XCTAssertEqual(WatchPalette.themeIDs, ["kyo", "neko", "techo"])
        for id in WatchPalette.themeIDs {
            XCTAssertEqual(WatchPalette.palette(forThemeID: id)?.themeID, id)
        }
        XCTAssertNil(WatchPalette.palette(forThemeID: "a-theme-from-a-newer-phone"))
    }

    func testAHexColorIsOpaqueAndReadsBackItsComponents() {
        let color = WatchPaletteColor.fixed(hex: 0xff8000)

        XCTAssertEqual(color.components, .init(red: 1, green: 128.0 / 255, blue: 0, opacity: 1))
    }

    /// The Kyo theme's colors are watchOS's own, so a test can't read them, except the card grey
    /// the Watch has always drawn at a fixed value, with its opacity.
    func testTheKyoThemesCardIsTodaysGreyAtTodaysOpacity() {
        XCTAssertEqual(WatchPalette.kyo.card.components, .init(red: 0.14, green: 0.14, blue: 0.15, opacity: 0.72))
        XCTAssertNil(WatchPalette.kyo.accent.components)
        XCTAssertNil(WatchPalette.kyo.secondaryText.components)
        XCTAssertNil(WatchPalette.kyo.onAccent)
    }
}
