import UIKit
import XCTest

/// Neko: Catppuccin's published Latte and Mocha values for the roles the spec names.
final class ThemeNekoTests: XCTestCase {
    private func hex(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    func testLightIsCatppuccinLatteWithMauveAsTheAccent() {
        let light = Theme.neko.light
        XCTAssertEqual(hex(light.screenBackground), "eff1f5", "Base")
        XCTAssertEqual(hex(light.card), "ccd0da", "Surface0")
        XCTAssertEqual(hex(light.primaryText), "4c4f69", "Text")
        XCTAssertEqual(hex(light.secondaryText), "5c5f77", "Subtext1")
        XCTAssertEqual(hex(light.tertiaryText), "6c6f85", "Subtext0")
        XCTAssertEqual(hex(light.accent), "8839ef", "Mauve")
    }

    func testDarkIsCatppuccinMochaWithMauveAsTheAccent() {
        let dark = Theme.neko.dark
        XCTAssertEqual(hex(dark.screenBackground), "1e1e2e", "Base")
        XCTAssertEqual(hex(dark.card), "313244", "Surface0")
        XCTAssertEqual(hex(dark.primaryText), "cdd6f4", "Text")
        XCTAssertEqual(hex(dark.secondaryText), "bac2de", "Subtext1")
        XCTAssertEqual(hex(dark.tertiaryText), "a6adc8", "Subtext0")
        XCTAssertEqual(hex(dark.accent), "cba6f7", "Mauve")
    }

    func testNekoHasNoLetterSpacingOfItsOwnToAdd() {
        XCTAssertEqual(Theme.neko.headerFont.tracking(for: .section), 0)
        XCTAssertEqual(Theme.neko.headerFont.tracking(for: .largeTitle), 0)
    }
}
