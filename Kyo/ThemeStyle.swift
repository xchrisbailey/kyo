import SwiftUI

/// The one current theme for the whole app. Every window on iPad reads this same instance, so a
/// theme chosen in one window shows in all of them.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var current: Theme = .kyo
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.kyo
}

extension EnvironmentValues {
    /// The theme every view takes its colors and header font from.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

private struct HeaderStyleModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let style: HeaderStyle

    func body(content: Content) -> some View {
        content
            .font(theme.headerFont.font(for: style))
            .tracking(theme.headerFont.tracking(for: style))
    }
}

private struct ThemedNavigationTitle: ViewModifier {
    @Environment(\.theme) private var theme
    let title: LocalizedStringKey

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .headerStyle(.navigationTitle)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

extension View {
    /// Sets text in the theme's header font for `style`. Headers take their font from here, so a
    /// theme with another header font restyles every one of them.
    func headerStyle(_ style: HeaderStyle) -> some View {
        modifier(HeaderStyleModifier(style: style))
    }

    /// The title of a screen in a navigation bar, set in the theme's header font. A screen iOS draws
    /// itself, such as the system event detail, doesn't use this and keeps iOS's title.
    func themedNavigationTitle(_ title: LocalizedStringKey) -> some View {
        modifier(ThemedNavigationTitle(title: title))
    }

    /// A list or form drawn on the theme's sheet background instead of iOS's own grouped one.
    func themedListBackground() -> some View {
        modifier(ThemedListBackground())
    }
}

private struct ThemedListBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.sheetBackground)
    }
}
