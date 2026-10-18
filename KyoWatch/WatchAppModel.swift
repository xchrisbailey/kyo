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
    let projectsPreference: WatchProjectsPreferenceStore
    let theme: WatchThemeStore
    let recordingDefaults: UserDefaults
    let isolatedRecordingDirectory: URL?
    private let transport: WatchConnectivityTaskTransport

    private init() {
        let stores = WatchStoreSelection.make()
        transport = stores.transport
        recordingDefaults = stores.recordingDefaults
        isolatedRecordingDirectory = stores.isolatedRecordingDirectory
        taskList = stores.taskList
        habitList = stores.habitList
        projectsPreference = ProjectsPreferenceSelection.makeWatch()
        theme = WatchThemeSelection.make(transport: { stores.transport })
        memoList = stores.memoList
    }

    /// The work of a Watch Connectivity background task: make sure the stores exist, then wait
    /// until the session is activated and has nothing pending, so what the phone sent is applied
    /// before the system is told the task is done.
    func handleWatchConnectivityRefresh() async {
        _ = Self.shared
        await WatchConnectivityRefresh.wait { self.transport.isActivatedWithNoPendingContent }
    }
}
