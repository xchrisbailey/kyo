import XCTest

/// Whether a theme draws a pinned bar, such as the audio player's, on a color of its own.
final class ThemeBarBackgroundTests: XCTestCase {
    func testTheKyoThemeKeepsTheSystemMaterial() {
        XCTAssertNil(Theme.kyo.barBackground)
        XCTAssertNil(Theme.kyo.light.barBackground)
        XCTAssertNil(Theme.kyo.dark.barBackground)
    }

    func testEveryOtherThemeSetsABarBackgroundInBothModes() {
        for theme in Theme.all where theme.id != Theme.kyo.id {
            XCTAssertNotNil(theme.light.barBackground, "\(theme.name) light")
            XCTAssertNotNil(theme.dark.barBackground, "\(theme.name) dark")
            XCTAssertNotNil(theme.barBackground, theme.name)
        }
    }
}
