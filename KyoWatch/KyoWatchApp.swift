import SwiftUI

@main
struct KyoWatchApp: App {
    // Owned by `WatchAppModel`, so a background launch has the phone's theme to adopt.
    @ObservedObject private var theme = WatchAppModel.shared.theme

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                // The palette every Watch view reads, sheets included, since they inherit it. A
                // theme that arrives while the app is on screen recolors it at once, not animated.
                .environment(\.watchPalette, theme.palette)
                // The text no view colors itself, such as titles and the recorder's timer.
                .foregroundStyle(theme.palette.primaryText.style)
                .transaction(value: theme.palette.themeID) { $0.animation = nil }
                // A complication's `widgetURL` (`kyo://record-memo`) opens Kyo into recording
                // through the same router as the Record memo control.
                .onOpenURL { url in
                    guard let action = QuickCaptureRouter.Action(url: url) else { return }
                    QuickCaptureRouter.shared.perform(action)
                }
        }
        // The phone's snapshots, including `acknowledgedMemoIDs`, can wake the Watch app in the
        // background. The task stays open until they've been applied.
        .backgroundTask(.watchConnectivity) {
            await WatchAppModel.shared.handleWatchConnectivityRefresh()
        }
    }
}
