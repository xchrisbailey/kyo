import Foundation

/// Picks where this launch keeps the theme choice and the palette preference: the device's own
/// defaults, or, for UI tests, a suite of their own.
enum ThemeSelection {
    /// UI tests set this to a suite name. A launch with the same name sees the theme and palette
    /// preference an earlier launch left, so a test can relaunch; a name nothing has used starts on
    /// the Kyo theme and System. Isolated launches without it get a throwaway suite, so they always
    /// start there and never read a developer's real choice.
    static let suiteEnvironmentKey = "KYO_THEME_SUITE"

    /// Launches that keep the theme away from the device's real choice (in memory, or in a suite of
    /// their own) publish nothing to the Watch, and never ask for the transport, so a test never
    /// activates a session or changes a paired Watch's theme.
    @MainActor
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        transport: () -> any ThemeIDTransport = { WatchConnectivityTaskTransport.shared }
    ) -> ThemeStore {
        if let isolated = isolatedDefaults(in: environment) {
            return ThemeStore(defaults: isolated)
        }
        return ThemeStore(defaults: defaults, transport: transport())
    }

    @MainActor
    static func makePalettePreferenceStore(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> PalettePreferenceStore {
        PalettePreferenceStore(defaults: isolatedDefaults(in: environment) ?? defaults)
    }

    /// The suite a launch keeps its choices in when it stays away from the device's real ones: the
    /// named suite, or a throwaway one for an in-memory launch. Nil for an ordinary launch.
    private static func isolatedDefaults(in environment: [String: String]) -> UserDefaults? {
        if let suite = environment[suiteEnvironmentKey], let named = UserDefaults(suiteName: suite) {
            return named
        }
        if KyoModelContainer.isInMemoryRequested(in: environment) {
            let suite = "kyo.theme.ui-tests.\(UUID().uuidString)"
            if let throwaway = UserDefaults(suiteName: suite) {
                throwaway.removePersistentDomain(forName: suite)
                return throwaway
            }
        }
        return nil
    }
}
