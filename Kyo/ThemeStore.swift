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
        current = defaults.string(forKey: Self.storageKey).flatMap(Theme.withID) ?? .kyo
    }

    /// Applies `theme` at once, in every window, and keeps the choice.
    func select(_ theme: Theme) {
        current = theme
        defaults.set(theme.id, forKey: Self.storageKey)
    }
}
