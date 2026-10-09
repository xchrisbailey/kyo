import SwiftUI
import UIKit

/// Sets the palette preference on the window that holds the view it is attached to. A window's
/// setting reaches everything iOS draws in it (sheets, alerts, menus, the keyboard, UIKit-hosted
/// screens), and going back to System returns an open sheet to the device's setting, which
/// `preferredColorScheme(nil)` doesn't. Each window attaches its own, so every window follows.
struct WindowPalette: UIViewRepresentable {
    let preference: PalettePreference

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.preference = preference
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.preference = preference
    }

    final class AnchorView: UIView {
        var preference = PalettePreference.system {
            didSet { apply() }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            window?.overrideUserInterfaceStyle = preference.userInterfaceStyle
        }
    }
}
