import AppIntents
import SwiftUI
import WidgetKit

/// The **Record memo** control for Control Center and the Lock Screen. It can also be assigned
/// to the Action button.
struct RecordMemoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "computer.srcery.kyo.control.record-memo") {
            ControlWidgetButton(action: RecordMemoIntent()) {
                Label("Record memo", systemImage: "mic.fill")
            }
        }
        .displayName("Record memo")
        .description("Open Kyo and start recording a voice memo.")
    }
}

/// The **Write memo** control for Control Center and the Lock Screen.
struct WriteMemoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "computer.srcery.kyo.control.write-memo") {
            ControlWidgetButton(action: WriteMemoIntent()) {
                Label("Write memo", systemImage: "square.and.pencil")
            }
        }
        .displayName("Write memo")
        .description("Open Kyo and write a memo.")
    }
}
