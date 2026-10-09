import UIKit
import XCTest

/// Techo: a paper planner in light and a chalkboard in dark, with Caveat for headers. The look is
/// reviewed from screenshots, and the contrast floors are in `ThemeContrastTests`; these pin what
/// neither shows.
final class ThemeTechoTests: XCTestCase {
    func testTechoIsAShippedTheme() {
        XCTAssertTrue(Theme.all.contains { $0.id == "techo" })
        XCTAssertEqual(Theme.withID("techo")?.name, "Techo")
    }

    /// Caveat sets no letter spacing of its own, so Techo adds none: the last glyph's room comes from
    /// a space after the text, which leaves the letters where the font puts them.
    func testTechoHeadersGetNoLetterSpacingAndTheirLastGlyphRoomFromATrailingSpace() {
        let header = Theme.techo.headerFont
        XCTAssertFalse(header.trailingRoom.isEmpty)
        for style in [HeaderStyle.section, .largeTitle, .navigationTitle] {
            XCTAssertEqual(header.tracking(for: style), 0, "\(style)")
        }
    }

    /// Caveat reads small, so Techo scales its headers up; the Kyo theme's stay as they are.
    func testTechoScalesItsHeadersUpAndTheKyoThemeDoesNot() {
        XCTAssertGreaterThan(Theme.techo.headerFont.sizeScale, 1)
        XCTAssertEqual(Theme.kyo.headerFont.sizeScale, 1)
    }

    /// The Kyo theme's headers are set exactly as before: no trailing room for glyph overhang and no
    /// per-style sizes.
    func testTheKyoThemeAddsNoTrailingRoomOrStyleSizes() {
        XCTAssertEqual(Theme.kyo.headerFont.trailingRoom, "")
        XCTAssertTrue(Theme.kyo.headerFont.styleSizeScales.isEmpty)
        XCTAssertEqual(Theme.neko.headerFont.trailingRoom, "")
    }

    /// In light the accent and destructive are both red, and they meet on screen: the "Delete habit"
    /// row and the recorder's Stop button. They differ enough in lightness to tell apart.
    func testLightAccentAndDestructiveAreTellableApart() {
        let light = Theme.techo.light
        XCTAssertGreaterThanOrEqual(RGBA.contrast(RGBA(light.accent), RGBA(light.destructive)), 1.5)
    }
}
