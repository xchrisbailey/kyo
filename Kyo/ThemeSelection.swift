import Foundation

/// Picks where this launch keeps the theme choice: the device's own defaults, or, for UI tests, a
/// suite of their own.
enum ThemeSelection {
    /// UI tests set this to a suite name. A launch with the same name sees the choice an earlier
    /// launch left, so a test can relaunch; a name nothing has used starts on the Kyo theme.
    /// Isolated launches without it get a throwaway suite, so they always start on the Kyo theme and
    /// never read a developer's real choice.
    static let suiteEnvironmentKey = "KYO_THEME_SUITE"

    /// Launches that keep the theme away from the device's real choice (in memory, or in a suite of
    /// their own) publish nothing to the Watch, so a test never changes a paired Watch's theme.
    @MainActor
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        transport: any ThemeIDTransport = WatchConnectivityTaskTransport.shared
    ) -> ThemeStore {
        if let suite = environment[suiteEnvironmentKey], let defaults = UserDefaults(suiteName: suite) {
            return ThemeStore(defaults: defaults)
        }
        if environment[KyoModelContainer.inMemoryEnvironmentKey] == "1" {
            let suite = "kyo.theme.ui-tests.\(UUID().uuidString)"
            if let defaults = UserDefaults(suiteName: suite) {
                defaults.removePersistentDomain(forName: suite)
                return ThemeStore(defaults: defaults)
            }
        }
        return ThemeStore(transport: transport)
    }
}
