import UIKit

extension HeaderFont.Face {
    /// Geist Mono, bundled in `Kyo/Fonts` and registered in `Config/Kyo-Info.plist`.
    static let geistMono = HeaderFont.Face.bundled(semibold: "GeistMono-SemiBold", bold: "GeistMono-Bold")
}

extension Theme {
    /// Catppuccin Latte in light and Catppuccin Mocha in dark, with Geist Mono for headers. Every
    /// color is a published value from the Catppuccin palette (github.com/catppuccin/palette,
    /// palette.json, v1.8.0), named for its role here by the Catppuccin color it is.
    static let neko = Theme(
        id: "neko",
        name: "Neko",
        headerFont: HeaderFont(face: .geistMono, sectionTracking: 0, largeTitleTracking: 0),
        light: Palette(
            screenBackground: Latte.base,
            sheetBackground: Latte.base,
            card: Latte.surface0,
            listRow: Latte.surface0,
            primaryText: Latte.text,
            secondaryText: Latte.subtext1,
            rowDetailText: Latte.subtext1,
            tertiaryText: Latte.subtext0,
            separator: Latte.surface1,
            fill: Latte.mantle,
            accent: Latte.mauve,
            controlTint: Latte.mauve,
            onAccent: Latte.base,
            onAccentText: Latte.base,
            todayNumeral: Latte.base,
            warning: Latte.peach,
            onWarning: Latte.base,
            destructive: Latte.red,
            onDestructive: Latte.base,
            scrim: Latte.text.withAlphaComponent(0.6),
            onScrim: Latte.base,
            kindEvents: Latte.overlay1,
            kindTasks: Latte.mauve,
            kindHabits: Latte.peach,
            kindMemos: Latte.blue
        ),
        dark: Palette(
            screenBackground: Mocha.base,
            sheetBackground: Mocha.base,
            card: Mocha.surface0,
            listRow: Mocha.surface0,
            primaryText: Mocha.text,
            secondaryText: Mocha.subtext1,
            rowDetailText: Mocha.subtext1,
            tertiaryText: Mocha.subtext0,
            separator: Mocha.surface1,
            fill: Mocha.surface1,
            accent: Mocha.mauve,
            controlTint: Mocha.mauve,
            onAccent: Mocha.base,
            onAccentText: Mocha.base,
            todayNumeral: Mocha.base,
            warning: Mocha.peach,
            onWarning: Mocha.base,
            destructive: Mocha.red,
            onDestructive: Mocha.base,
            scrim: Mocha.crust.withAlphaComponent(0.6),
            onScrim: Mocha.text,
            kindEvents: Mocha.overlay1,
            kindTasks: Mocha.mauve,
            kindHabits: Mocha.peach,
            kindMemos: Mocha.blue
        )
    )
}

/// Catppuccin Latte, the light flavor. Only the colors Neko uses.
private enum Latte {
    static let text = UIColor(hex: 0x4c4f69)
    static let subtext1 = UIColor(hex: 0x5c5f77)
    static let subtext0 = UIColor(hex: 0x6c6f85)
    static let overlay1 = UIColor(hex: 0x8c8fa1)
    static let surface1 = UIColor(hex: 0xbcc0cc)
    static let surface0 = UIColor(hex: 0xccd0da)
    static let base = UIColor(hex: 0xeff1f5)
    static let mantle = UIColor(hex: 0xe6e9ef)
    static let mauve = UIColor(hex: 0x8839ef)
    static let red = UIColor(hex: 0xd20f39)
    static let peach = UIColor(hex: 0xfe640b)
    static let blue = UIColor(hex: 0x1e66f5)
}

/// Catppuccin Mocha, the dark flavor. Only the colors Neko uses.
private enum Mocha {
    static let text = UIColor(hex: 0xcdd6f4)
    static let subtext1 = UIColor(hex: 0xbac2de)
    static let subtext0 = UIColor(hex: 0xa6adc8)
    static let overlay1 = UIColor(hex: 0x7f849c)
    static let surface1 = UIColor(hex: 0x45475a)
    static let surface0 = UIColor(hex: 0x313244)
    static let base = UIColor(hex: 0x1e1e2e)
    static let crust = UIColor(hex: 0x11111b)
    static let mauve = UIColor(hex: 0xcba6f7)
    static let red = UIColor(hex: 0xf38ba8)
    static let peach = UIColor(hex: 0xfab387)
    static let blue = UIColor(hex: 0x89b4fa)
}

extension UIColor {
    /// An opaque color from a 0xRRGGBB value, for the themes that name their colors that way.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
