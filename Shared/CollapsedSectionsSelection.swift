import Foundation

/// Picks where this launch keeps which sections are collapsed: the device's own defaults, or, for UI
/// tests, a suite of their own. The phone and the Watch share it.
enum CollapsedSectionsSelection {
    /// UI tests set this to a suite name. A launch with the same name sees the state an earlier
    /// launch left, so a test can relaunch; a name nothing has used starts with every section expanded.
    /// Isolated launches without it get a throwaway suite, so they always start expanded.
    static let suiteEnvironmentKey = "KYO_COLLAPSED_SECTIONS_SUITE"

    @MainActor
    static func make() -> CollapsedSections {
        let environment = ProcessInfo.processInfo.environment
        if let suite = environment[suiteEnvironmentKey], let defaults = UserDefaults(suiteName: suite) {
            return CollapsedSections(defaults: defaults)
        }
        if KyoModelContainer.isInMemoryRequested {
            let suite = "kyo.collapsed-sections.ui-tests.\(UUID().uuidString)"
            if let defaults = UserDefaults(suiteName: suite) {
                defaults.removePersistentDomain(forName: suite)
                return CollapsedSections(defaults: defaults)
            }
        }
        return CollapsedSections()
    }
}
