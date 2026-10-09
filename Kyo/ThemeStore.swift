import SwiftUI

/// The one current theme for the whole app. Every window on iPad reads this same instance, so a
/// theme chosen in one window shows in all of them.
///
/// The choice is kept in the device's own `UserDefaults`, so each device keeps its own theme. It
/// isn't synced between phones and isn't in the SwiftData store. The one exception is the Apple
/// Watch, which shows the iPhone's theme: the store publishes its id to the transport when it
/// starts and whenever the theme changes (see `docs/adr/0007-watch-follows-the-phone-theme.md`).
/// The theme is Kyo until the user picks another, and again when the stored value names no theme
/// the app ships.
@MainActor
final class ThemeStore: ObservableObject {
    static let storageKey = "kyo.theme.v1"

    /// The store the app and all its windows share, kept where this launch keeps the choice.
    static let shared = ThemeSelection.make()

    @Published private(set) var current: Theme
    private let defaults: UserDefaults
    private let transport: (any ThemeIDTransport)?

    /// With a `transport`, the current theme's id is published at once. Without one, such as in a
    /// test or a launch that keeps its store in memory, nothing is.
    init(defaults: UserDefaults = .standard, transport: (any ThemeIDTransport)? = nil) {
        self.defaults = defaults
        self.transport = transport
        current = defaults.string(forKey: Self.storageKey).flatMap(Theme.withID) ?? .kyo
        transport?.publish(themeID: current.id)
    }

    /// Applies `theme` at once, in every window, and keeps the choice.
    func select(_ theme: Theme) {
        current = theme
        defaults.set(theme.id, forKey: Self.storageKey)
        transport?.publish(themeID: theme.id)
    }
}
