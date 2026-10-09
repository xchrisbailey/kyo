import SwiftUI

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

/// A header's text in the theme's header font, followed by the font's trailing room.
private struct HeaderText: View {
    @Environment(\.theme) private var theme
    let text: Text
    let style: HeaderStyle

    var body: some View {
        let header = theme.headerFont
        let shown = header.trailingRoom.isEmpty ? text : text + Text(header.trailingRoom)
        shown
            .font(header.font(for: style))
            .tracking(header.tracking(for: style))
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

extension Text {
    /// A header's text, in the theme's header font for `style`, with the room that font needs after
    /// its last glyph. It goes on the `Text` itself, since that room is part of the text.
    func headerStyle(_ style: HeaderStyle) -> some View {
        HeaderText(text: self, style: style)
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

/// A group of rows in a list or form, with the theme's row background and, when it has a title, the
/// title as a group header in the theme's secondary text color. Lists use it in place of a plain
/// `Section` so a group can't miss either. A group with no title has no header.
struct ThemedListGroup<Content: View>: View {
    @Environment(\.theme) private var theme
    private let title: Text?
    private let content: Content

    /// A group headed by a localized `title`.
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    /// A group headed by `title` as given, such as a name that comes from the data.
    init<S: StringProtocol>(verbatim title: S, @ViewBuilder content: () -> Content) {
        self.title = Text(verbatim: String(title))
        self.content = content()
    }

    /// A group with no header.
    init(@ViewBuilder content: () -> Content) {
        self.title = nil
        self.content = content()
    }

    var body: some View {
        Group {
            if let title {
                Section {
                    content
                } header: {
                    title.foregroundStyle(theme.secondaryText)
                }
            } else {
                Section {
                    content
                }
            }
        }
        .listRowBackground(theme.listRow)
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
