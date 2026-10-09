import UIKit
import XCTest

/// Every theme's palettes against the contrast floors in `docs/specs/themes.md`, in both modes:
/// primary text 4.5:1 against each background it sits on; secondary text, the accent, and the colors
/// drawn on the accent, on a warning, and on a destructive fill 3:1; warning and destructive used as
/// text 3:1. Tertiary text has no floor. A color is resolved for the mode and blended with the
/// background behind it before it is measured, so a translucent color isn't read as an opaque one.
/// A theme added to `Theme.all` is covered with no new test.
final class ThemeContrastTests: XCTestCase {
    private typealias Role = KeyPath<Palette, UIColor>

    /// A background a color is measured against. A translucent one, such as the Kyo theme's `fill` or
    /// a capsule tinted at 12%, is drawn over the opaque role in `over` and measured as blended.
    private struct Backdrop {
        let name: String
        let role: Role
        var over: Role?
        var alpha: Double

        init(_ name: String, _ role: Role, over: Role? = nil, alpha: Double = 1) {
            self.name = name
            self.role = role
            self.over = over
            self.alpha = alpha
        }
    }

    private let screenBackground = Backdrop("screenBackground", \.screenBackground)
    private let sheetBackground = Backdrop("sheetBackground", \.sheetBackground)
    private let card = Backdrop("card", \.card)
    private let listRow = Backdrop("listRow", \.listRow)
    /// The weekday chip sits on a row.
    private let fill = Backdrop("fill", \.fill, over: \.listRow)

    /// Where text sits: every surface a screen is drawn on.
    private var surfaces: [Backdrop] { [screenBackground, sheetBackground, card, listRow] }

    private let modes: [(name: String, style: UIUserInterfaceStyle)] = [("light", .light), ("dark", .dark)]

    /// Pairs a theme misses today, with the ratio it reaches. The Kyo theme must look as it always
    /// has, and Neko uses only Catppuccin's published values with no published color that both passes
    /// and suits the role, so the color is left alone and the miss is recorded here. The test fails
    /// if one of these starts to pass, so the entry goes when the color is fixed.
    private let knownShortfalls: Set<String> = [
        "Kyo dark onAccentText on accent",  // 1.87:1
        "Kyo light onWarning on warning",  // 2.31:1
        "Kyo dark onWarning on warning",  // 2.23:1
        "Kyo light warning on screenBackground",  // 2.07:1
        "Kyo light warning on sheetBackground",  // 2.07:1
        "Kyo light destructive on screenBackground with destructive tint",  // 2.74:1
        "Kyo light destructive on sheetBackground with destructive tint",  // 2.74:1
        // No published Latte orange or yellow reaches 3:1 on Base or on the white of an on-warning
        // label, and the Latte colors that do (red, mauve, blue) are Neko's destructive and accent.
        "Neko light onWarning on warning",  // 2.64:1 (Base); Text on Peach is 2.68:1
        "Neko light warning on screenBackground",  // 2.64:1
        "Neko light warning on sheetBackground",  // 2.64:1
    ]

    func testPrimaryTextMeetsAAOnEveryBackground() {
        assertEveryTheme(foreground: ("primaryText", \.primaryText), on: surfaces + [fill], floor: 4.5)
    }

    func testSecondaryTextMeetsThreeToOneOnEveryBackground() {
        assertEveryTheme(foreground: ("secondaryText", \.secondaryText), on: surfaces, floor: 3)
    }

    func testTheDetailLineOfAListRowMeetsThreeToOneOnTheRow() {
        assertEveryTheme(foreground: ("rowDetailText", \.rowDetailText), on: [listRow], floor: 3)
    }

    func testAccentMeetsThreeToOneOnEveryBackground() {
        assertEveryTheme(foreground: ("accent", \.accent), on: surfaces, floor: 3)
    }

    /// Switches, plain buttons and carets are drawn in the control tint on the screen and on the
    /// surfaces. A theme that keeps iOS's tint has none to measure.
    func testControlTintMeetsThreeToOneOnEveryBackground() {
        let themes = Theme.all.filter { $0.light.controlTint != nil && $0.dark.controlTint != nil }
        XCTAssertTrue(themes.contains { $0.id == "techo" })
        assertEveryTheme(foreground: ("controlTint", \.controlTintOrAccent), on: surfaces, floor: 3, themes: themes)
    }

    func testColorsDrawnOnTheAccentMeetThreeToOneAgainstIt() {
        let accent = Backdrop("accent", \.accent)
        for foreground in [
            ("onAccent", \Palette.onAccent), ("onAccentText", \Palette.onAccentText),
            ("todayNumeral", \Palette.todayNumeral),
        ] {
            assertEveryTheme(foreground: foreground, on: [accent], floor: 3)
        }
    }

    func testColorsDrawnOnAWarningAndOnADestructiveFillMeetThreeToOneAgainstIt() {
        assertEveryTheme(foreground: ("onWarning", \.onWarning), on: [Backdrop("warning", \.warning)], floor: 3)
        assertEveryTheme(foreground: ("onDestructive", \.onDestructive), on: [Backdrop("destructive", \.destructive)], floor: 3)
    }

    /// "Paused" and the cap note are warning-colored text on the recorder's and a memo's backgrounds.
    func testWarningTextMeetsThreeToOneWhereItIsDrawn() {
        assertEveryTheme(foreground: ("warning", \.warning), on: [screenBackground, sheetBackground], floor: 3)
    }

    /// "Delete habit" is destructive text on a row; the memo's Delete and the recorder's Discard are
    /// destructive text on a capsule tinted with the destructive color at 12%.
    func testDestructiveTextMeetsThreeToOneWhereItIsDrawn() {
        assertEveryTheme(
            foreground: ("destructive", \.destructive),
            on: [
                listRow, screenBackground, sheetBackground,
                Backdrop("screenBackground with destructive tint", \.destructive, over: \.screenBackground, alpha: 0.12),
                Backdrop("sheetBackground with destructive tint", \.destructive, over: \.sheetBackground, alpha: 0.12),
            ],
            floor: 3
        )
    }

    func testTheKyoThemeKeepsItsHeaderLetterSpacing() {
        XCTAssertEqual(Theme.kyo.headerFont.tracking(for: .section), -0.4)
        XCTAssertEqual(Theme.kyo.headerFont.tracking(for: .largeTitle), -1.2)
        XCTAssertEqual(Theme.kyo.headerFont.tracking(for: .navigationTitle), 0)
    }

    // MARK: Measuring

    private func assertEveryTheme(
        foreground: (name: String, role: Role), on backgrounds: [Backdrop], floor: Double,
        themes: [Theme] = Theme.all,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for theme in themes {
            for mode in modes {
                for background in backgrounds {
                    assertContrast(theme, mode, foreground: foreground, background: background, floor: floor, file: file, line: line)
                }
            }
        }
    }

    private func assertContrast(
        _ theme: Theme, _ mode: (name: String, style: UIUserInterfaceStyle),
        foreground: (name: String, role: Role), background: Backdrop, floor: Double,
        file: StaticString, line: UInt
    ) {
        let palette = theme.palette(for: mode.style)
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: mode.style),
            UITraitCollection(userInterfaceLevel: .base),
        ])
        func resolved(_ role: Role) -> RGBA { RGBA(palette[keyPath: role].resolvedColor(with: traits)) }
        var back = resolved(background.role).applying(alpha: background.alpha)
        if let under = background.over {
            back = back.blended(over: resolved(under))
        }
        XCTAssertEqual(back.alpha, 1, "\(theme.name) \(mode.name) \(background.name) is translucent", file: file, line: line)
        let front = resolved(foreground.role).blended(over: back)
        let ratio = RGBA.contrast(front, back)
        let pair = "\(theme.name) \(mode.name) \(foreground.name) on \(background.name)"
        let isKnown = knownShortfalls.contains(pair)
        if isKnown {
            XCTAssertLessThan(ratio, floor, "\(pair) now meets \(floor):1; remove it from knownShortfalls", file: file, line: line)
        } else {
            XCTAssertGreaterThanOrEqual(
                ratio, floor, "\(pair) is \(String(format: "%.2f", ratio)):1, below \(floor):1", file: file, line: line
            )
        }
    }
}

private extension Palette {
    /// The control tint, for the themes that set one; the others are filtered out before it is read.
    var controlTintOrAccent: UIColor { controlTint ?? accent }
}
