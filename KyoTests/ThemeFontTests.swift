import CoreText
import XCTest

/// The header fonts the themes name are the ones the app bundles and registers.
final class ThemeFontTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Each file in `Kyo/Fonts` registers a face with exactly the PostScript name a theme asks for,
    /// so a header can't fall back silently.
    func testEveryFaceAThemeNamesIsInTheBundledFontFiles() throws {
        let fonts = root.appendingPathComponent("Kyo/Fonts")
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

        for theme in Theme.all {
            for name in theme.headerFont.face.postScriptNames {
                XCTAssertTrue(
                    registered.contains(name), "\(theme.name) names \(name), which isn't in Kyo/Fonts: \(registered.sorted())"
                )
            }
        }
    }

    /// Every bundled font file is registered with the app, or its face would fall back.
    func testEveryBundledFontFileIsRegisteredInTheInfoPlist() throws {
        let plist = try Data(contentsOf: root.appendingPathComponent("Config/Kyo-Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        let listed = Set(info?["UIAppFonts"] as? [String] ?? [])
        let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Kyo/Fonts").path)
        XCTAssertEqual(Set(files.filter { $0.hasSuffix(".ttf") }), listed)
    }
}
