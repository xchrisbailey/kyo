import UIKit

extension HeaderFont.Face {
    /// Caveat, bundled in `Kyo/Fonts` and registered in `Config/Kyo-Info.plist`.
    static let caveat = HeaderFont.Face.bundled(semibold: "Caveat-SemiBold", bold: "Caveat-Bold")
}

extension Theme {
    /// A paper planner in light and a chalkboard in dark, with the handwritten Caveat for headers.
    ///
    /// Light is cream paper under ink, with a red margin-line accent; cards and rows are a lighter
    /// sheet laid on it. Dark is a slate-green board under chalk, with a chalk-yellow accent, so
    /// what is drawn on the accent is dark ink-on-chalk in dark and cream in light. Destructive is
    /// a deep wine against the margin line's vermilion, so the two reds stay apart where they meet,
    /// as on the "Delete habit" row and the recorder's Stop button.
    ///
    /// Caveat reads smaller than the system font at the same point size, so its headers are scaled
    /// up until they look as large as the Kyo theme's.
    static let techo = Theme(
        id: "techo",
        name: "Techo",
        headerFont: HeaderFont(
            face: .caveat, sizeScale: 1.3,
            styleSizeScales: [.section: 1.4, .navigationTitle: 1.55],
            overhangAllowance: 2, sectionTracking: 0, largeTitleTracking: 0
        ),
        light: Palette(
            screenBackground: Paper.cream,
            sheetBackground: Paper.cream,
            card: Paper.sheet,
            listRow: Paper.sheet,
            primaryText: Paper.ink,
            secondaryText: Paper.inkSoft,
            tertiaryText: Paper.inkFaint,
            separator: Paper.rule,
            fill: Paper.shade,
            accent: Paper.margin,
            controlTint: Paper.margin,
            onAccent: Paper.sheet,
            onAccentText: Paper.sheet,
            todayNumeral: Paper.sheet,
            warning: Paper.ochre,
            onWarning: Paper.sheet,
            destructive: Paper.wine,
            onDestructive: Paper.sheet,
            scrim: Paper.ink.withAlphaComponent(0.6),
            onScrim: Paper.sheet,
            kindEvents: Paper.graphite,
            kindTasks: Paper.blue,
            kindHabits: Paper.green,
            kindMemos: Paper.plum
        ),
        dark: Palette(
            screenBackground: Chalkboard.slate,
            sheetBackground: Chalkboard.slate,
            card: Chalkboard.panel,
            listRow: Chalkboard.panel,
            primaryText: Chalkboard.chalk,
            secondaryText: Chalkboard.chalkSoft,
            tertiaryText: Chalkboard.chalkFaint,
            separator: Chalkboard.rule,
            fill: Chalkboard.shade,
            accent: Chalkboard.yellow,
            controlTint: Chalkboard.yellow,
            onAccent: Chalkboard.slate,
            onAccentText: Chalkboard.slate,
            todayNumeral: Chalkboard.slate,
            warning: Chalkboard.orange,
            onWarning: Chalkboard.slate,
            destructive: Chalkboard.rose,
            onDestructive: Chalkboard.slate,
            scrim: UIColor.black.withAlphaComponent(0.6),
            onScrim: Chalkboard.chalk,
            kindEvents: Chalkboard.dust,
            kindTasks: Chalkboard.blue,
            kindHabits: Chalkboard.green,
            kindMemos: Chalkboard.lilac
        )
    )
}

/// Techo's light palette: paper, ink and the pencils and pens used on it.
private enum Paper {
    static let cream = UIColor(hex: 0xf3ebd8)
    static let sheet = UIColor(hex: 0xfbf6e9)
    static let ink = UIColor(hex: 0x1c2438)
    static let inkSoft = UIColor(hex: 0x525a6b)
    static let inkFaint = UIColor(hex: 0x8d8f95)
    static let rule = UIColor(hex: 0xd9ceb4)
    static let shade = UIColor(hex: 0xe6dcc3)
    static let margin = UIColor(hex: 0xc8402f)
    static let wine = UIColor(hex: 0x8a1c34)
    static let ochre = UIColor(hex: 0xa85f0a)
    static let graphite = UIColor(hex: 0x857f72)
    static let blue = UIColor(hex: 0x33608f)
    static let green = UIColor(hex: 0x4d7b3b)
    static let plum = UIColor(hex: 0x7b4b8c)
}

/// Techo's dark palette: a slate-green board and the colors of chalk on it.
private enum Chalkboard {
    static let slate = UIColor(hex: 0x1d2a26)
    static let panel = UIColor(hex: 0x283631)
    static let chalk = UIColor(hex: 0xeef0e4)
    static let chalkSoft = UIColor(hex: 0xb8c2b6)
    static let chalkFaint = UIColor(hex: 0x7f8b83)
    static let rule = UIColor(hex: 0x3d4b45)
    static let shade = UIColor(hex: 0x36443e)
    static let yellow = UIColor(hex: 0xf2d974)
    static let rose = UIColor(hex: 0xf0877d)
    static let orange = UIColor(hex: 0xf0a265)
    static let dust = UIColor(hex: 0x9aa69d)
    static let blue = UIColor(hex: 0x8fb9de)
    static let green = UIColor(hex: 0x9ccf88)
    static let lilac = UIColor(hex: 0xc5a5d8)
}
