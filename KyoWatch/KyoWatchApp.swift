import SwiftUI

@main
struct KyoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTodayView()
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
