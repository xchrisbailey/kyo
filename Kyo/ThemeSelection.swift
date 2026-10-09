import Foundation

/// Picks where this launch keeps the theme choice and the palette preference: the device's own
/// defaults, or, for UI tests, a suite of their own.
enum ThemeSelection {
    /// UI tests set this to a suite name. A launch with the same name sees the theme and palette
    /// preference an earlier launch left, so a test can relaunch; a name nothing has used starts on
    /// the Kyo theme and System. Isolated launches without it get a throwaway suite, so they always
    /// start there and never read a developer's real choice.
    static let suiteEnvironmentKey = "KYO_THEME_SUITE"

    @MainActor
    static func make() -> ThemeStore {
        ThemeStore(defaults: defaults())
    }

    @MainActor
    static func makePalettePreferenceStore() -> PalettePreferenceStore {
        PalettePreferenceStore(defaults: defaults())
    }

    private static func defaults() -> UserDefaults {
        let environment = ProcessInfo.processInfo.environment
        if let suite = environment[suiteEnvironmentKey], let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        if KyoModelContainer.isInMemoryRequested {
            let suite = "kyo.theme.ui-tests.\(UUID().uuidString)"
            if let defaults = UserDefaults(suiteName: suite) {
                defaults.removePersistentDomain(forName: suite)
                return defaults
            }
        }
        return .standard
    }
}
