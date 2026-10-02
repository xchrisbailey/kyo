import SwiftUI

@main
struct KyoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTodayView()
        }
        // The phone's snapshots, including `acknowledgedMemoIDs`, can wake the Watch app in the
        // background. The task stays open until they've been applied.
        .backgroundTask(.watchConnectivity) {
            await WatchAppModel.shared.handleWatchConnectivityRefresh()
        }
    }
}
