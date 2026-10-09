import SwiftUI

/// One color a Watch palette names. It is either a watchOS system color, which a test can't read,
/// or a fixed color value, whose components it can. A surface's opacity belongs to the entry, never
/// to the view that draws it.
struct WatchPaletteColor: Sendable {
    struct Components: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
        var opacity: Double
    }

    /// For the places SwiftUI takes a `Color`: a button's tint, a strikethrough.
    let color: Color
    /// For `foregroundStyle`, `fill` and `background`. It differs from `color` only where a view
    /// draws with a hierarchical style, such as secondary, which SwiftUI resolves against the
    /// context it's drawn in rather than as a fixed color.
    let style: AnyShapeStyle
    /// The fixed value, or `nil` for a watchOS system color. With a separate light value, the dark one.
    let components: Components?

    /// A watchOS system color, or an expression built from one, such as `Color.primary.opacity(0.12)`.
    static func system(_ color: Color) -> WatchPaletteColor {
        WatchPaletteColor(color: color, style: AnyShapeStyle(color), components: nil)
    }

    /// A system color that views draw with `style` where they use a hierarchical style, such as
    /// `Color.secondary` drawn as `.secondary`.
    static func system(_ color: Color, style: some ShapeStyle) -> WatchPaletteColor {
        WatchPaletteColor(color: color, style: AnyShapeStyle(style), components: nil)
    }

    /// A color value that a test can read back.
    static func fixed(red: Double, green: Double, blue: Double, opacity: Double = 1) -> WatchPaletteColor {
        let color = Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
        return WatchPaletteColor(
            color: color,
            style: AnyShapeStyle(color),
            components: Components(red: red, green: green, blue: blue, opacity: opacity)
        )
    }

    /// An entry with a value for each of the device's appearances. watchOS is always dark, so the
    /// light value never draws there; the Kyo theme keeps the ones the Watch's code already had.
    static func appearance(dark: WatchPaletteColor, light: WatchPaletteColor) -> WatchPaletteColor {
        WatchPaletteColor(
            color: dark.color,
            style: AnyShapeStyle(AppearanceStyle(dark: dark.style, light: light.style)),
            components: dark.components
        )
    }

    private struct AppearanceStyle: ShapeStyle {
        let dark: AnyShapeStyle
        let light: AnyShapeStyle

        func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
            environment.colorScheme == .dark ? dark : light
        }
    }
}

/// The colors the Apple Watch app sets itself, for one theme. A role no view can do without is added
/// here, never worked around with a system color in the view. The phone's `Palette` is built on
/// iOS-only color APIs and isn't compiled into the Watch, so the Watch keeps its own, keyed by the
/// same theme ids.
struct WatchPalette: Sendable {
    /// The id of the theme it belongs to.
    let themeID: String

    /// Today's summary.
    let card: WatchPaletteColor
    /// A row of a section.
    let listRow: WatchPaletteColor
    /// The line between two rows.
    let divider: WatchPaletteColor

    let accent: WatchPaletteColor
    let primaryText: WatchPaletteColor
    let secondaryText: WatchPaletteColor
    let warning: WatchPaletteColor
    /// Also colors recording.
    let destructive: WatchPaletteColor
    /// The tint of a task row's Edit button.
    let editTint: WatchPaletteColor

    /// The label drawn on a button filled with the accent, the warning color, or the destructive
    /// color. `nil` leaves the label to watchOS, which is what the Kyo theme does.
    let onAccent: WatchPaletteColor?
    let onWarning: WatchPaletteColor?
    let onDestructive: WatchPaletteColor?

    /// Every theme the Watch has a palette for.
    static let all: [WatchPalette] = [.kyo]

    /// The ids of the themes the Watch has a palette for.
    static var themeIDs: [String] { all.map(\.themeID) }

    /// The palette for the theme stored as `id`, or `nil` when the Watch has none for it.
    static func palette(forThemeID id: String) -> WatchPalette? {
        all.first { $0.themeID == id }
    }

    /// The Kyo theme: the look the Watch has always had, in watchOS's own colors and styles.
    static let kyo = WatchPalette(
        themeID: "kyo",
        card: .appearance(
            dark: .fixed(red: 0.14, green: 0.14, blue: 0.15, opacity: 0.72),
            light: .fixed(red: 1, green: 1, blue: 1, opacity: 0.92)
        ),
        listRow: .appearance(
            dark: .system(Color.primary.opacity(0.12)),
            light: .system(Color.primary.opacity(0.06))
        ),
        divider: .system(Color.primary.opacity(0.08)),
        accent: .system(.green),
        primaryText: .system(.primary),
        secondaryText: .system(.secondary, style: HierarchicalShapeStyle.secondary),
        warning: .system(.orange),
        destructive: .system(.red),
        editTint: .system(.blue),
        onAccent: nil,
        onWarning: nil,
        onDestructive: nil
    )
}

private struct WatchPaletteKey: EnvironmentKey {
    static let defaultValue = WatchPalette.kyo
}

extension EnvironmentValues {
    /// The current Watch palette. The Kyo theme until something sets another.
    var watchPalette: WatchPalette {
        get { self[WatchPaletteKey.self] }
        set { self[WatchPaletteKey.self] = newValue }
    }
}
