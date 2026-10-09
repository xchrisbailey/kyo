import CoreText
import UIKit
import XCTest

/// Techo: a paper planner in light and a chalkboard in dark, with Caveat for headers. The look is
/// reviewed from screenshots; these pin what a screenshot can't show.
final class ThemeTechoTests: XCTestCase {
    private func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ value: CGFloat) -> Double {
            Double(value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4))
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    func testTechoIsAShippedTheme() {
        XCTAssertTrue(Theme.all.contains { $0.id == "techo" })
        XCTAssertEqual(Theme.named("techo")?.name, "Techo")
    }

    func testTechoUsesCaveatsOwnLetterSpacing() {
        XCTAssertEqual(Theme.techo.headerFont.tracking(for: .section), 0)
        XCTAssertEqual(Theme.techo.headerFont.tracking(for: .largeTitle), 0)
    }

    /// Caveat reads small, so Techo scales its headers up; the Kyo theme's stay as they are.
    func testTechoScalesItsHeadersUpAndTheKyoThemeDoesNot() {
        XCTAssertGreaterThan(Theme.techo.headerFont.sizeScale, 1)
        XCTAssertEqual(Theme.kyo.headerFont.sizeScale, 1)
    }

    /// In light the accent and destructive are both red, and they meet on screen: the "Delete habit"
    /// row and the recorder's Stop button. They differ enough in lightness to tell apart.
    func testLightAccentAndDestructiveAreTellableApart() {
        let light = Theme.techo.light
        XCTAssertGreaterThanOrEqual(contrast(light.accent, light.destructive), 1.5)
    }

    /// Dark mode's accent is chalk yellow, so what is drawn on it is a dark mark, not a white one.
    func testTheMarkOnTheChalkYellowAccentIsDark() {
        let dark = Theme.techo.dark
        XCTAssertLessThan(luminance(dark.onAccent), luminance(dark.accent))
        XCTAssertLessThan(luminance(dark.onAccentText), luminance(dark.accent))
        XCTAssertLessThan(luminance(dark.todayNumeral), luminance(dark.accent))
    }

    /// The fonts the header font names are the ones in `Kyo/Fonts`: each file registers a face with
    /// exactly the PostScript name the theme asks for, so a header can't fall back silently.
    func testEveryFaceTechoNamesIsInTheBundledFontFiles() throws {
        let fonts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Kyo/Fonts")
        var registered: Set<String> = []
        for file in try FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)
        where file.pathExtension == "ttf" {
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] ?? []
            for descriptor in descriptors {
                if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                    registered.insert(name)
                }
            }
        }

        let named = Theme.techo.headerFont.face.postScriptNames
        XCTAssertEqual(named.count, 2)
        for name in named {
            XCTAssertTrue(registered.contains(name), "\(name) isn't in Kyo/Fonts, which has \(registered.sorted())")
        }
    }

    /// Every bundled font file is registered with the app, or its face would fall back.
    func testEveryBundledFontFileIsRegisteredInTheInfoPlist() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let plist = try Data(contentsOf: root.appendingPathComponent("Config/Kyo-Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        let listed = Set(info?["UIAppFonts"] as? [String] ?? [])
        let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Kyo/Fonts").path)
        XCTAssertEqual(Set(files.filter { $0.hasSuffix(".ttf") }), listed)
    }
}
