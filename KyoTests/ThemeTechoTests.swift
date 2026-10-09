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

    /// Caveat sets no letter spacing of its own, so the tracking a Techo header gets is only the
    /// allowance that keeps the last glyph from being clipped by the text's bounds: the glyph reaches
    /// past its advance, and SwiftUI can only add room for it as tracking.
    func testTechoHeadersGetOnlyTheOverhangAllowanceAsTracking() {
        let header = Theme.techo.headerFont
        XCTAssertEqual(header.overhangAllowance, 2)
        for style in [HeaderStyle.section, .largeTitle, .navigationTitle] {
            XCTAssertEqual(header.tracking(for: style), header.overhangAllowance, "\(style)")
        }
    }

    /// Caveat reads small, so Techo scales its headers up; the Kyo theme's stay as they are.
    func testTechoScalesItsHeadersUpAndTheKyoThemeDoesNot() {
        XCTAssertGreaterThan(Theme.techo.headerFont.sizeScale, 1)
        XCTAssertEqual(Theme.kyo.headerFont.sizeScale, 1)
    }

    /// The Kyo theme's headers are set exactly as before: no extra tracking for glyph overhang and no
    /// per-style sizes.
    func testTheKyoThemeAddsNoOverhangAllowanceOrStyleSizes() {
        XCTAssertEqual(Theme.kyo.headerFont.overhangAllowance, 0)
        XCTAssertTrue(Theme.kyo.headerFont.styleSizeScales.isEmpty)
        XCTAssertEqual(Theme.neko.headerFont.overhangAllowance, 0)
    }

    /// In light the accent and destructive are both red, and they meet on screen: the "Delete habit"
    /// row and the recorder's Stop button. They differ enough in lightness to tell apart.
    func testLightAccentAndDestructiveAreTellableApart() {
        let light = Theme.techo.light
        XCTAssertGreaterThanOrEqual(RGBA.contrast(RGBA(light.accent), RGBA(light.destructive)), 1.5)
    }

    private func hex(_ color: UIColor?) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Switches and plain buttons take the control tint. In light that is the pen blue, so an "on"
    /// switch isn't red; the accent stays the margin-line vermilion for what asks for the accent.
    func testLightControlsAreTintedPenBlueWhileTheAccentStaysVermilion() {
        let light = Theme.techo.light
        XCTAssertEqual(hex(light.controlTint), "33608f", "pen blue")
        XCTAssertEqual(hex(light.accent), "c8402f", "vermilion")
    }

    /// In dark the chalk yellow serves as both.
    func testDarkControlTintIsTheChalkYellowAccent() {
        let dark = Theme.techo.dark
        XCTAssertEqual(hex(dark.controlTint), hex(dark.accent))
    }
}
