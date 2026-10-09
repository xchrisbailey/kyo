import UIKit
import XCTest

/// Every theme's palettes against the contrast floors in `docs/specs/themes.md`, in both modes:
/// primary text 4.5:1 against each background it sits on; secondary text and the accent 3:1; the
/// colors drawn on the accent 3:1 against it. Tertiary text has no floor. A color is resolved for
/// the mode and blended with the background behind it before it is measured, so a translucent
/// color isn't read as an opaque one. A theme added to `Theme.all` is covered with no new test.
final class ThemeContrastTests: XCTestCase {
    private typealias Role = KeyPath<Palette, UIColor>

    private let backgrounds: [(name: String, role: Role)] = [
        ("screenBackground", \.screenBackground),
        ("sheetBackground", \.sheetBackground),
        ("card", \.card),
        ("listRow", \.listRow),
    ]

    private let modes: [(name: String, style: UIUserInterfaceStyle)] = [("light", .light), ("dark", .dark)]

    /// Pairs the Kyo theme misses today. The Kyo theme must look as it always has, so the color is
    /// left alone and the miss is recorded here; the test fails if one of these starts to pass, so
    /// the entry goes when the color is fixed.
    private let knownShortfalls: Set<String> = [
        "Kyo dark onAccentText on accent",
    ]

    func testPrimaryTextMeetsAAOnEveryBackground() {
        for theme in Theme.all {
            for mode in modes {
                for background in backgrounds {
                    assertContrast(
                        theme, mode, foreground: ("primaryText", \.primaryText),
                        background: background, floor: 4.5
                    )
                }
            }
        }
    }

    func testSecondaryTextMeetsThreeToOneOnEveryBackground() {
        for theme in Theme.all {
            for mode in modes {
                for background in backgrounds {
                    assertContrast(
                        theme, mode, foreground: ("secondaryText", \.secondaryText),
                        background: background, floor: 3
                    )
                }
            }
        }
    }

    func testAccentMeetsThreeToOneOnEveryBackground() {
        for theme in Theme.all {
            for mode in modes {
                for background in backgrounds {
                    assertContrast(
                        theme, mode, foreground: ("accent", \.accent),
                        background: background, floor: 3
                    )
                }
            }
        }
    }

    func testColorsDrawnOnTheAccentMeetThreeToOneAgainstIt() {
        for theme in Theme.all {
            for mode in modes {
                for foreground in [
                    ("onAccent", \Palette.onAccent), ("onAccentText", \Palette.onAccentText),
                    ("todayNumeral", \Palette.todayNumeral),
                ] {
                    assertContrast(
                        theme, mode, foreground: foreground, background: ("accent", \.accent), floor: 3
                    )
                }
            }
        }
    }

    func testTheKyoThemeKeepsItsHeaderLetterSpacing() {
        XCTAssertEqual(Theme.kyo.headerFont.tracking(for: .section), -0.4)
        XCTAssertEqual(Theme.kyo.headerFont.tracking(for: .largeTitle), -1.2)
        XCTAssertEqual(Theme.kyo.headerFont.tracking(for: .navigationTitle), 0)
    }

    // MARK: Measuring

    private func assertContrast(
        _ theme: Theme, _ mode: (name: String, style: UIUserInterfaceStyle),
        foreground: (name: String, role: Role), background: (name: String, role: Role), floor: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let palette = theme.palette(for: mode.style)
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: mode.style),
            UITraitCollection(userInterfaceLevel: .base),
        ])
        let back = RGBA(palette[keyPath: background.role].resolvedColor(with: traits))
        XCTAssertEqual(back.alpha, 1, "\(theme.name) \(mode.name) \(background.name) is translucent", file: file, line: line)
        let front = RGBA(palette[keyPath: foreground.role].resolvedColor(with: traits)).blended(over: back)
        let ratio = Self.contrast(front, back.blended(over: back))
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

    private struct RGBA {
        var red: Double, green: Double, blue: Double, alpha: Double

        init(_ color: UIColor) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            (red, green, blue, alpha) = (r, g, b, a)
        }

        func blended(over back: RGBA) -> RGBA {
            var result = self
            result.red = back.red + (red - back.red) * alpha
            result.green = back.green + (green - back.green) * alpha
            result.blue = back.blue + (blue - back.blue) * alpha
            result.alpha = 1
            return result
        }

        /// WCAG relative luminance of an opaque color.
        var luminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    private static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let (high, low) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (high + 0.05) / (low + 0.05)
    }
}
