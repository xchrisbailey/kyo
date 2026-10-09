import UIKit
import XCTest

/// The Apple Watch's palettes against the phone's themes. Neko and Techo on the Watch are fixed
/// values equal to the phone's dark palette for the matching role; a theme on one side only fails.
final class WatchThemeParityTests: XCTestCase {
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    private func components(_ color: UIColor) -> WatchPaletteColor.Components {
        let value = RGBA(color.resolvedColor(with: dark))
        return .init(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    private func assertEqual(
        _ watch: WatchPaletteColor?, _ phone: UIColor?, _ role: String, theme: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let watch = watch?.components, let phone else {
            return XCTFail("\(theme) \(role) has no fixed value on the Watch or no color on the phone", file: file, line: line)
        }
        let expected = components(phone)
        XCTAssertEqual(watch.red, expected.red, accuracy: 1e-9, "\(theme) \(role) red", file: file, line: line)
        XCTAssertEqual(watch.green, expected.green, accuracy: 1e-9, "\(theme) \(role) green", file: file, line: line)
        XCTAssertEqual(watch.blue, expected.blue, accuracy: 1e-9, "\(theme) \(role) blue", file: file, line: line)
        XCTAssertEqual(watch.opacity, expected.opacity, accuracy: 1e-9, "\(theme) \(role) opacity", file: file, line: line)
    }

    func testTheWatchHasAPaletteForEveryThemeThePhoneShipsAndNoOther() {
        XCTAssertEqual(Set(WatchPalette.themeIDs), Set(Theme.all.map(\.id)))
        XCTAssertEqual(WatchPalette.themeIDs.count, Theme.all.count)
    }

    func testEachNekoAndTechoWatchColorEqualsThePhonesDarkValueForItsRole() throws {
        for id in ["neko", "techo"] {
            let phone = try XCTUnwrap(Theme.withID(id)).dark
            let watch = try XCTUnwrap(WatchPalette.palette(forThemeID: id))
            assertEqual(watch.accent, phone.accent, "accent", theme: id)
            assertEqual(watch.card, phone.card, "card", theme: id)
            assertEqual(watch.listRow, phone.listRow, "row", theme: id)
            assertEqual(watch.divider, phone.separator, "divider", theme: id)
            assertEqual(watch.primaryText, phone.primaryText, "primary text", theme: id)
            assertEqual(watch.secondaryText, phone.secondaryText, "secondary text", theme: id)
            assertEqual(watch.tertiaryText, phone.tertiaryText, "tertiary text", theme: id)
            assertEqual(watch.warning, phone.warning, "warning", theme: id)
            assertEqual(watch.destructive, phone.destructive, "destructive", theme: id)
            assertEqual(watch.onAccent, phone.onAccentText, "label on accent", theme: id)
            assertEqual(watch.onWarning, phone.onWarning, "label on warning", theme: id)
            assertEqual(watch.onDestructive, phone.onDestructive, "label on destructive", theme: id)
            // The Edit swipe action's glyph is drawn white by watchOS, so Neko and Techo keep the system
            // tint there instead of the phone's control tint, which is light.
            XCTAssertNil(watch.editTint.components, "\(id) Edit tint is watchOS's own")
        }
    }

    /// The Kyo theme's Watch colors are watchOS's own, which a test can't read, except the card grey.
    func testTheKyoThemeOnTheWatchIsNotMeasuredAgainstThePhone() throws {
        let kyo = try XCTUnwrap(WatchPalette.palette(forThemeID: "kyo"))
        XCTAssertNil(kyo.accent.components)
        XCTAssertNil(kyo.primaryText.components)
        XCTAssertNil(kyo.destructive.components)
    }
}

/// Neko's and Techo's Watch palettes against the phone's contrast floors (`docs/specs/themes.md`),
/// on true black and on the card: primary text 4.5:1; secondary text and the accent 3:1; a button's
/// label against its fill 3:1. The Kyo theme's colors are watchOS system colors and aren't measured.
final class WatchThemeContrastTests: XCTestCase {
    private let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)

    private var measured: [WatchPalette] {
        WatchPalette.all.filter { $0.themeID != "kyo" }
    }

    private func rgba(_ color: WatchPaletteColor?, _ role: String, _ theme: String) throws -> RGBA {
        let value = try XCTUnwrap(color?.components, "\(theme) \(role) has no fixed value")
        return RGBA(red: value.red, green: value.green, blue: value.blue, alpha: value.opacity)
    }

    private func assertContrast(
        _ role: String, _ foreground: KeyPath<WatchPalette, WatchPaletteColor>, on backgrounds: [(String, KeyPath<WatchPalette, WatchPaletteColor>?)],
        floor: Double, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(measured.map(\.themeID), ["neko", "techo"], file: file, line: line)
        for palette in measured {
            for (name, background) in backgrounds {
                let back = try background.map { try rgba(palette[keyPath: $0], name, palette.themeID) } ?? black
                XCTAssertEqual(back.alpha, 1, "\(palette.themeID) \(name) is translucent", file: file, line: line)
                let front = try rgba(palette[keyPath: foreground], role, palette.themeID).blended(over: back)
                let ratio = RGBA.contrast(front, back)
                XCTAssertGreaterThanOrEqual(
                    ratio, floor, "\(palette.themeID) \(role) on \(name) is \(String(format: "%.2f", ratio)):1, below \(floor):1",
                    file: file, line: line
                )
            }
        }
    }

    private var onBlackAndCard: [(String, KeyPath<WatchPalette, WatchPaletteColor>?)] {
        [("black", nil), ("card", \.card)]
    }

    func testPrimaryTextMeetsAAOnBlackAndOnTheCard() throws {
        try assertContrast("primary text", \.primaryText, on: onBlackAndCard, floor: 4.5)
    }

    func testSecondaryTextMeetsThreeToOneOnBlackAndOnTheCard() throws {
        try assertContrast("secondary text", \.secondaryText, on: onBlackAndCard, floor: 3)
    }

    func testTheAccentMeetsThreeToOneOnBlackAndOnTheCard() throws {
        try assertContrast("accent", \.accent, on: onBlackAndCard, floor: 3)
    }

    func testWarningAndDestructiveMeetThreeToOneOnBlackAndOnTheCard() throws {
        try assertContrast("warning", \.warning, on: onBlackAndCard, floor: 3)
        try assertContrast("destructive", \.destructive, on: onBlackAndCard, floor: 3)
    }

    func testTheLabelOfAFilledButtonMeetsThreeToOneAgainstItsFill() throws {
        for palette in measured {
            for (role, label, fill) in [
                ("accent", palette.onAccent, palette.accent),
                ("warning", palette.onWarning, palette.warning),
                ("destructive", palette.onDestructive, palette.destructive),
            ] {
                let back = try rgba(fill, "\(role) fill", palette.themeID)
                let front = try rgba(label, "label on \(role)", palette.themeID).blended(over: back)
                let ratio = RGBA.contrast(front, back)
                XCTAssertGreaterThanOrEqual(
                    ratio, 3, "\(palette.themeID) label on \(role) fill is \(String(format: "%.2f", ratio)):1, below 3:1"
                )
            }
        }
    }
}

extension RGBA {
    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.init(UIColor(red: red, green: green, blue: blue, alpha: alpha))
    }
}
