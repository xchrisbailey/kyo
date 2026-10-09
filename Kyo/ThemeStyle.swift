import SwiftUI

/// The one current theme for the whole app. Every window on iPad reads this same instance, so a
/// theme chosen in one window shows in all of them.
///
/// The choice is kept in the device's own `UserDefaults`, so each device keeps its own theme. It
/// isn't synced and isn't in the SwiftData store. The theme is Kyo until the user picks another,
/// and again when the stored value names no theme the app ships.
@MainActor
final class ThemeStore: ObservableObject {
    static let storageKey = "kyo.theme.v1"

    /// The store the app and all its windows share, kept where this launch keeps the choice.
    static let shared = ThemeSelection.make()

    @Published private(set) var current: Theme
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        current = defaults.string(forKey: Self.storageKey).flatMap(Theme.named) ?? .kyo
    }

    /// Applies `theme` at once, in every window, and keeps the choice.
    func select(_ theme: Theme) {
        current = theme
        defaults.set(theme.id, forKey: Self.storageKey)
    }
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
            .tracking(theme.headerFont.tracking(for: style) + theme.headerFont.overhangAllowance)
    }
}

private struct ThemedText: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(theme.primaryText)
    }
}

private struct ThemedTint: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.tint(theme.controlTint)
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
    /// Sets the text color of everything below that names none to the theme's primary text color.
    /// It goes on a screen's content and not on its navigation bar, so bar buttons keep iOS's own
    /// styling, disabled state included.
    func themedText() -> some View {
        modifier(ThemedText())
    }

    /// Tints the controls below with the theme's control tint, or leaves iOS's own when it has none.
    func themedTint() -> some View {
        modifier(ThemedTint())
    }

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
            .themedText()
            .background(theme.sheetBackground)
    }
}
