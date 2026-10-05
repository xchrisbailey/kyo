import AppIntents
import SwiftUI
import WidgetKit

/// The Watch's **Record memo** control, for Control Center, the Smart Stack and the Action button
/// on Apple Watch Ultra. It's the Watch's own: iPhone controls that open the iPhone app don't
/// appear on the Watch.
struct WatchRecordMemoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "computer.srcery.kyo.watch.control.record-memo") {
            ControlWidgetButton(action: WatchRecordMemoIntent()) {
                Label("Record memo", systemImage: "mic.fill")
            }
        }
        .displayName("Record memo")
        .description("Open Kyo and start recording a voice memo.")
    }
}

/// The **Record memo** complication. Tapping it opens Kyo on the Watch and starts recording.
struct RecordMemoComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "computer.srcery.kyo.watch.complication.record-memo", provider: RecordMemoProvider()) { _ in
            RecordMemoComplicationView()
        }
        .configurationDisplayName("Record memo")
        .description("Open Kyo and start recording a voice memo.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

/// The complication never changes, so it has one entry and no refresh.
struct RecordMemoProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

struct RecordMemoComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            // A complication can't run an intent from a tap, so the tap opens Kyo with this URL,
            // which the Watch app routes to **Record memo**.
            .widgetURL(QuickCaptureRouter.Action.recordMemoURL)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "mic.fill")
                .font(.title.weight(.semibold))
                .widgetLabel("Record")
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Record memo").font(.headline)
                    Text("Tap to record").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("Record memo", systemImage: "mic.fill")
        default:
            Image(systemName: "mic.fill")
                .font(.title2.weight(.semibold))
        }
    }
}
