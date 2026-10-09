import SwiftUI

extension View {
    /// Draws the label of a filled button in the palette's color for it, or leaves it as watchOS draws it.
    @ViewBuilder
    func buttonLabelColor(_ color: WatchPaletteColor?) -> some View {
        if let color {
            foregroundStyle(color.style)
        } else {
            self
        }
    }
}
