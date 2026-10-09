import SwiftUI
import UIKit

/// The user's choice of which of a theme's palettes shows. System follows the device's light or dark
/// setting; Light and Dark keep that palette whatever the device is set to.
enum PalettePreference: String, CaseIterable {
    case system, light, dark

    /// The segment's text and what VoiceOver reads for it.
    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What every window of the app is set to; `.unspecified` hands the choice back to the device.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The one palette preference for the whole app. Every window on iPad reads this same instance, so a
/// preference chosen in one window shows in all of them. It applies to whichever theme is current.
///
/// The choice is kept in the device's own `UserDefaults`, so each device keeps its own. It isn't
/// synced and isn't in the SwiftData store. The preference is System until the user picks another,
/// and again when the stored value names no current preference.
@MainActor
final class PalettePreferenceStore: ObservableObject {
    static let storageKey = "kyo.palettePreference.v1"

    /// The store the app and all its windows share, kept where this launch keeps the choice.
    static let shared = ThemeSelection.makePalettePreferenceStore()

    @Published private(set) var current: PalettePreference
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        current = defaults.string(forKey: Self.storageKey).flatMap(PalettePreference.init(rawValue:)) ?? .system
    }

    /// Applies `preference` at once, in every window, and keeps the choice.
    func select(_ preference: PalettePreference) {
        current = preference
        defaults.set(preference.rawValue, forKey: Self.storageKey)
    }
}
