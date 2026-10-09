import SwiftUI

/// The Appearance group's palette control: System, Light, or Dark in a segmented control with no
/// visible label. Tapping a segment applies it at once.
struct PalettePicker: View {
    @ObservedObject var store: PalettePreferenceStore

    var body: some View {
        Picker("Palette", selection: Binding(get: { store.current }, set: { store.select($0) })) {
            ForEach(PalettePreference.allCases, id: \.self) { preference in
                Text(preference.name).tag(preference)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Palette")
        .accessibilityIdentifier("palette-picker")
    }
}
