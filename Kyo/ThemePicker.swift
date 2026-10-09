import SwiftUI
import UIKit

/// The Appearance group's picker: one preview card per theme, the current one marked. Tapping a card
/// applies that theme at once.
struct ThemePicker: View {
    @ObservedObject var store: ThemeStore

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(Theme.all, id: \.id) { theme in
                ThemePreviewCard(theme: theme, isSelected: store.current.id == theme.id) {
                    store.select(theme)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A theme shown by its light and dark colors side by side and its name in its own header font.
/// It reads to VoiceOver as one button with the theme's name, selected or not.
private struct ThemePreviewCard: View {
    @Environment(\.theme) private var current
    let theme: Theme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ThemePreviewSwatch(palette: theme.light, style: .light)
                    ThemePreviewSwatch(palette: theme.dark, style: .dark)
                }
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(current.separator, lineWidth: 1)
                }
                HStack(spacing: 6) {
                    Text(theme.name)
                        .headerStyle(.section)
                        .environment(\.theme, theme)
                        .foregroundStyle(current.primaryText)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(current.accent)
                    }
                }
            }
            .padding(8)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? current.accent : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("theme-card-\(theme.id)")
    }
}

/// Half a preview: a screen in one palette with a card holding two lines of text and the accent.
private struct ThemePreviewSwatch: View {
    let palette: Palette
    let style: UIUserInterfaceStyle

    var body: some View {
        ZStack {
            color(palette.screenBackground)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color(palette.card))
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(color(palette.primaryText)).frame(width: 34, height: 4)
                        Capsule().fill(color(palette.secondaryText)).frame(width: 22, height: 4)
                    }
                    .padding(.leading, 8)
                }
                .overlay(alignment: .trailing) {
                    Circle().fill(color(palette.accent)).frame(width: 12, height: 12).padding(.trailing, 8)
                }
                .frame(height: 34)
                .padding(.horizontal, 8)
        }
    }

    /// The color as the palette's own mode draws it, whatever mode the device is in.
    private func color(_ uiColor: UIColor) -> Color {
        Color(uiColor: uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
    }
}
