import SwiftUI
import UIKit

/// A named look for the app: a light palette, a dark palette, and a header font. The device's light
/// or dark setting decides which palette shows. A view reads every color from the theme in its
/// environment, never from a system color or a literal.
struct Theme {
    /// What the device stores to remember the choice, so it never changes for a shipped theme.
    let id: String
    let name: String
    let headerFont: HeaderFont
    let light: Palette
    let dark: Palette

    /// Every theme the app ships.
    static let all: [Theme] = [.kyo, .neko, .techo]

    /// The shipped theme stored as `id`, or `nil` when none is.
    static func named(_ id: String) -> Theme? {
        all.first { $0.id == id }
    }

    /// The palette drawn when the device is in `style`.
    func palette(for style: UIUserInterfaceStyle) -> Palette {
        style == .dark ? dark : light
    }
}

/// The colors a theme names. A role no view can do without is added here, never worked around with
/// a system color in the view.
///
/// Each role is a `UIColor` so a theme can use a dynamic system color that still follows a sheet's
/// raised background and Increase Contrast. A palette's colors are the ones shown in its own mode:
/// resolve one with that mode's trait collection to read it.
struct Palette {
    /// Behind Today and the Month, and behind a full-screen cover.
    var screenBackground: UIColor
    /// Behind a sheet and the lists inside one.
    var sheetBackground: UIColor
    /// The surface of a Today section and of a memo row.
    var card: UIColor
    /// A row or card in a grouped list, and the Month's grid and Day summary.
    var listRow: UIColor

    var primaryText: UIColor
    var secondaryText: UIColor
    /// Hints and disabled states, and the ring of an unchecked circle.
    var tertiaryText: UIColor
    var separator: UIColor
    /// The resting fill of a small control, such as an unselected weekday chip.
    var fill: UIColor

    var accent: UIColor
    /// The tint of controls that take one: switches, text carets, plain button labels, pickers.
    /// `nil` leaves iOS's own tint, which is what the Kyo theme uses.
    var controlTint: UIColor?
    /// A checkmark drawn on a circle filled with the accent.
    var onAccent: UIColor
    /// Text and icons drawn on a solid accent fill: the Add button, the Save capsule, the play button.
    var onAccentText: UIColor
    /// The day number drawn on the accent circle that marks today in the Month.
    var todayNumeral: UIColor

    var warning: UIColor
    var onWarning: UIColor
    /// Also colors recording.
    var destructive: UIColor
    var onDestructive: UIColor

    /// A translucent plate over a photo, behind a control drawn on it.
    var scrim: UIColor
    var onScrim: UIColor

    var kindEvents: UIColor
    var kindTasks: UIColor
    var kindHabits: UIColor
    var kindMemos: UIColor
}

extension Theme {
    /// The color for `role`: the light palette's in light and the dark palette's in dark, chosen as
    /// SwiftUI draws it so it follows the device and each sheet's own appearance.
    private func color(_ role: KeyPath<Palette, UIColor>) -> Color {
        let light = light[keyPath: role]
        let dark = dark[keyPath: role]
        return Color(uiColor: UIColor { traits in
            (traits.userInterfaceStyle == .dark ? dark : light).resolvedColor(with: traits)
        })
    }

    var screenBackground: Color { color(\.screenBackground) }
    var sheetBackground: Color { color(\.sheetBackground) }
    var card: Color { color(\.card) }
    var listRow: Color { color(\.listRow) }
    var primaryText: Color { color(\.primaryText) }
    var secondaryText: Color { color(\.secondaryText) }
    var tertiaryText: Color { color(\.tertiaryText) }
    var separator: Color { color(\.separator) }
    var fill: Color { color(\.fill) }
    var accent: Color { color(\.accent) }
    /// `nil` when the theme keeps iOS's tint. A theme sets a tint in both modes or in neither.
    var controlTint: Color? {
        guard let light = light.controlTint, let dark = dark.controlTint else { return nil }
        return Color(uiColor: UIColor { traits in
            (traits.userInterfaceStyle == .dark ? dark : light).resolvedColor(with: traits)
        })
    }
    var onAccent: Color { color(\.onAccent) }
    var onAccentText: Color { color(\.onAccentText) }
    var todayNumeral: Color { color(\.todayNumeral) }
    var warning: Color { color(\.warning) }
    var onWarning: Color { color(\.onWarning) }
    var destructive: Color { color(\.destructive) }
    var onDestructive: Color { color(\.onDestructive) }
    var scrim: Color { color(\.scrim) }
    var onScrim: Color { color(\.onScrim) }
    var kindEvents: Color { color(\.kindEvents) }
    var kindTasks: Color { color(\.kindTasks) }
    var kindHabits: Color { color(\.kindHabits) }
    var kindMemos: Color { color(\.kindMemos) }
}

/// What a header is: a role on screen, not a size. The theme's header font decides how each looks.
enum HeaderStyle {
    /// A section header on Today, a day group in Memos, the summary title in the Month.
    case section
    /// The large title of Today and the Month's month name.
    case largeTitle
    /// A navigation bar title.
    case navigationTitle
}

/// The typeface a theme sets headers in, with its letter spacing. The Kyo theme's is the system
/// font at the sizes and weights headers have always had.
struct HeaderFont {
    enum Face {
        case system
        /// A typeface bundled with the app, named by the PostScript names of its semibold and bold
        /// faces. Naming each weight keeps iOS from picking another face when one is missing.
        case bundled(semibold: String, bold: String)

        /// The PostScript names this face needs registered with the app.
        var postScriptNames: [String] {
            switch self {
            case .system: []
            case .bundled(let semibold, let bold): [semibold, bold]
            }
        }
    }

    var face: Face = .system
    /// Scales every header size, for a face that reads smaller or larger than the system font at the
    /// same point size, so its headers look as big as the Kyo theme's.
    var sizeScale: CGFloat = 1
    var sectionTracking: CGFloat
    var largeTitleTracking: CGFloat

    func font(for style: HeaderStyle) -> Font {
        switch face {
        case .system:
            switch style {
            case .section: .title3.weight(.semibold)
            case .largeTitle: .largeTitle.weight(.bold)
            case .navigationTitle: .headline
            }
        case .bundled(let semibold, let bold):
            // The point sizes are the system text styles' at the default text size, and the font
            // scales from them with the device text size, as the system styles do.
            switch style {
            case .section: .custom(semibold, size: 20 * sizeScale, relativeTo: .title3)
            case .largeTitle: .custom(bold, size: 34 * sizeScale, relativeTo: .largeTitle)
            case .navigationTitle: .custom(semibold, size: 17 * sizeScale, relativeTo: .headline)
            }
        }
    }

    func tracking(for style: HeaderStyle) -> CGFloat {
        switch style {
        case .section: sectionTracking
        case .largeTitle: largeTitleTracking
        case .navigationTitle: 0
        }
    }
}

extension Theme {
    /// The look Kyo has always had, and the default. Its colors are system colors, not copies, so
    /// they still shift for a sheet's raised background and for Increase Contrast.
    static let kyo = Theme(
        id: "kyo",
        name: "Kyo",
        headerFont: HeaderFont(sectionTracking: -0.4, largeTitleTracking: -1.2),
        light: Palette(
            screenBackground: .systemGroupedBackground,
            sheetBackground: .systemGroupedBackground,
            card: .white,
            listRow: .secondarySystemGroupedBackground,
            primaryText: .label,
            secondaryText: .secondaryLabel,
            tertiaryText: .tertiaryLabel,
            separator: .separator,
            fill: .tertiarySystemFill,
            accent: UIColor(red: 0.22, green: 0.43, blue: 0.34, alpha: 1),
            controlTint: nil,
            onAccent: .secondarySystemBackground,
            onAccentText: .white,
            todayNumeral: .systemBackground,
            warning: .systemOrange,
            onWarning: .white,
            destructive: .systemRed,
            onDestructive: .white,
            scrim: UIColor.black.withAlphaComponent(0.6),
            onScrim: .white,
            kindEvents: .systemGray,
            kindTasks: UIColor(red: 0.22, green: 0.43, blue: 0.34, alpha: 1),
            kindHabits: .systemOrange,
            kindMemos: .systemIndigo
        ),
        dark: Palette(
            screenBackground: .systemGroupedBackground,
            sheetBackground: .systemGroupedBackground,
            card: UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1),
            listRow: .secondarySystemGroupedBackground,
            primaryText: .label,
            secondaryText: .secondaryLabel,
            tertiaryText: .tertiaryLabel,
            separator: .separator,
            fill: .tertiarySystemFill,
            accent: UIColor(red: 0.57, green: 0.79, blue: 0.68, alpha: 1),
            controlTint: nil,
            onAccent: .secondarySystemBackground,
            onAccentText: .white,
            todayNumeral: .systemBackground,
            warning: .systemOrange,
            onWarning: .white,
            destructive: .systemRed,
            onDestructive: .white,
            scrim: UIColor.black.withAlphaComponent(0.6),
            onScrim: .white,
            kindEvents: .systemGray,
            kindTasks: UIColor(red: 0.57, green: 0.79, blue: 0.68, alpha: 1),
            kindHabits: .systemOrange,
            kindMemos: .systemIndigo
        )
    )
}
