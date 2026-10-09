import Foundation

/// Carries the id of the theme chosen on the phone to the Watch, in the application context that
/// carries the snapshots (see `docs/adr/0007-watch-follows-the-phone-theme.md`). The phone
/// publishes and the Watch receives; the Watch never asks and never replies.
@MainActor
protocol ThemeIDTransport: AnyObject {
    /// Makes `themeID` the latest theme available to the counterpart. Latest wins.
    func publish(themeID: String)
    /// Registers the receiver. If an id was already received, deliver the latest one immediately.
    /// A context that carries no id calls the receiver with nothing.
    func setThemeIDHandler(_ handler: @escaping @MainActor (String) -> Void)
}

/// The theme the Apple Watch app wears: the one the phone last sent.
///
/// The id is kept in the device's own `UserDefaults`, so the Watch still has its last theme with
/// the phone out of reach and after a relaunch. The Watch has no choice of its own: it shows the
/// Kyo theme until the phone has sent an id, and for an id it has no palette for, which stays
/// stored so the Watch switches once its app knows that theme.
@MainActor
final class WatchThemeStore: ObservableObject {
    static let storageKey = "kyo.watchTheme.v1"

    @Published private(set) var palette: WatchPalette
    private let defaults: UserDefaults

    /// With a `transport`, ids the phone sends are adopted as they arrive, including one that
    /// arrived before this model existed.
    init(defaults: UserDefaults = .standard, transport: (any ThemeIDTransport)? = nil) {
        self.defaults = defaults
        palette = Self.palette(storedIn: defaults)
        transport?.setThemeIDHandler { [weak self] themeID in
            self?.receive(themeID: themeID)
        }
    }

    /// Shows `themeID`'s palette, or the Kyo theme's when the Watch has none, and keeps the id.
    func receive(themeID: String) {
        defaults.set(themeID, forKey: Self.storageKey)
        palette = WatchPalette.palette(forThemeID: themeID) ?? .kyo
    }

    private static func palette(storedIn defaults: UserDefaults) -> WatchPalette {
        defaults.string(forKey: storageKey).flatMap(WatchPalette.palette(forThemeID:)) ?? .kyo
    }
}

/// Picks where this launch keeps the Watch's theme: the device's own defaults fed by the phone, or,
/// for UI tests and screenshot runs, a suite of their own that the phone can't reach.
enum WatchThemeSelection {
    /// A launch with this set to a suite name sees the id an earlier launch (or a harness) left
    /// there, so a run can start the Watch in a chosen theme. It takes no feed from the phone and
    /// writes only to that suite, so a paired simulator can't recolor the run or leave its theme in
    /// the real defaults. Isolated launches without it get a throwaway suite, likewise unfed, so they
    /// start in the Kyo theme and write nothing lasting.
    static let suiteEnvironmentKey = "KYO_WATCH_THEME_SUITE"

    @MainActor
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        transport: () -> any ThemeIDTransport = { WatchConnectivityTaskTransport.shared }
    ) -> WatchThemeStore {
        if let suite = environment[suiteEnvironmentKey], let suiteDefaults = UserDefaults(suiteName: suite) {
            return WatchThemeStore(defaults: suiteDefaults)
        }
        if KyoModelContainer.isInMemoryRequested(in: environment) {
            let suite = "kyo.watch-theme.ui-tests.\(UUID().uuidString)"
            if let throwaway = UserDefaults(suiteName: suite) {
                throwaway.removePersistentDomain(forName: suite)
                return WatchThemeStore(defaults: throwaway)
            }
        }
        return WatchThemeStore(defaults: defaults, transport: transport())
    }
}
