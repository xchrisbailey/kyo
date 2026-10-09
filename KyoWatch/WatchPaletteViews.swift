import SwiftUI

/// What a button is filled with when the fill is solid. The role gives the fill and the label drawn
/// on it together, so one can't be set without the other.
enum WatchFillRole {
    case accent
    case warning
    case destructive
}

extension WatchPalette {
    /// The fill for `role` and the color of a label on it. `nil` leaves the label to watchOS, which
    /// is what the Kyo theme does.
    func fill(for role: WatchFillRole) -> (fill: WatchPaletteColor, label: WatchPaletteColor?) {
        switch role {
        case .accent: (accent, onAccent)
        case .warning: (warning, onWarning)
        case .destructive: (destructive, onDestructive)
        }
    }
}

private struct SolidFill: ViewModifier {
    let role: WatchFillRole
    @Environment(\.watchPalette) private var palette

    func body(content: Content) -> some View {
        let colors = palette.fill(for: role)
        if let label = colors.label {
            content.tint(colors.fill.color).foregroundStyle(label.style)
        } else {
            content.tint(colors.fill.color)
        }
    }
}

extension View {
    /// Fills a `.borderedProminent` button with the palette's color for `role` and draws its label in
    /// the color the palette names for it. Don't use it on a bordered button, whose fill is a faint
    /// tint and whose label watchOS draws in the tint.
    func solidFill(_ role: WatchFillRole) -> some View {
        modifier(SolidFill(role: role))
    }
}
