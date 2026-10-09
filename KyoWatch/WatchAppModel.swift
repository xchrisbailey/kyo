import Foundation

/// The Watch's stores, made once for the life of the process. They live here, not in
/// `WatchTodayView`, so a launch in the background (`.backgroundTask(.watchConnectivity)`, when
/// the phone's snapshot arrives while the app isn't open) has them to apply it: the memo list
/// retires acknowledged outbox recordings and deletes their files, and the task and habit
/// lists take their snapshots, and the theme store adopts the phone's theme. Creating them
/// registers their handlers with the transport, which hands over any snapshot it already holds.
@MainActor
final class WatchAppModel {
    static let shared = WatchAppModel()

    let taskList: TaskListStore
    let habitList: HabitListStore
    let memoList: WatchMemoList
    let theme: WatchThemeStore

    private init() {
        let transport = WatchConnectivityTaskTransport.shared
        taskList = TaskListStore(sync: .mirror(from: transport))
        habitList = HabitListStore(sync: .mirror(from: transport))
        theme = WatchThemeSelection.make(transport: { transport })
        memoList = WatchMemoList(outbox: WatchRecordingOutbox(transport: transport), sync: transport)
    }

    /// The work of a Watch Connectivity background task: make sure the stores exist, then wait
    /// until the session is activated and has nothing pending, so what the phone sent is applied
    /// before the system is told the task is done.
    func handleWatchConnectivityRefresh() async {
        _ = Self.shared
        let transport = WatchConnectivityTaskTransport.shared
        await WatchConnectivityRefresh.wait { transport.isActivatedWithNoPendingContent }
    }
}
