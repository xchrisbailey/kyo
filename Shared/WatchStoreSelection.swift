import Foundation

/// The Watch's content stores and the one transport they share. Isolated launches use a fresh
/// cache suite and recording directory, and a session that cannot receive real phone content.
@MainActor
struct WatchStores {
    let taskList: TaskListStore
    let habitList: HabitListStore
    let memoList: WatchMemoList
    let transport: WatchConnectivityTaskTransport
    let recordingDefaults: UserDefaults
    let isolatedRecordingDirectory: URL?
}

@MainActor
enum WatchStoreSelection {
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        transport: () -> WatchConnectivityTaskTransport = { .shared },
        recordingDirectory: URL = WatchRecordingOutbox.defaultDirectory
    ) -> WatchStores {
        let selectedDefaults: UserDefaults
        let selectedTransport: WatchConnectivityTaskTransport
        let selectedDirectory: URL
        if KyoModelContainer.isInMemoryRequested(in: environment) {
            selectedDefaults = UserDefaults(suiteName: "kyo.watchContent.ui-tests.\(UUID().uuidString)")!
            selectedTransport = WatchConnectivityTaskTransport(session: nil)
            selectedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("kyo-watch-outbox-\(UUID().uuidString)")
        } else {
            selectedDefaults = defaults
            selectedTransport = transport()
            selectedDirectory = recordingDirectory
        }
        let tasks = TaskListStore(userDefaults: selectedDefaults, sync: .mirror(from: selectedTransport))
        let habits = HabitListStore(userDefaults: selectedDefaults, sync: .mirror(from: selectedTransport))
        let outbox = WatchRecordingOutbox(userDefaults: selectedDefaults, directory: selectedDirectory, transport: selectedTransport)
        let memos = WatchMemoList(userDefaults: selectedDefaults, outbox: outbox, sync: selectedTransport)
        return WatchStores(taskList: tasks, habitList: habits, memoList: memos, transport: selectedTransport,
            recordingDefaults: selectedDefaults,
            isolatedRecordingDirectory: KyoModelContainer.isInMemoryRequested(in: environment)
                ? selectedDirectory.appendingPathComponent("PartialRecordings") : nil)
    }
}
