/// A test double for `TaskSnapshotTransport` that lets tests control delivery timing:
/// connect/disconnect, redeliver old snapshots, and replay the latest one on reconnect.
@MainActor
final class ControllableTaskTransport: TaskSnapshotTransport {
    private(set) var published: [TaskListSnapshot] = []   // only to drive redelivery, never asserted on
    private var handler: (@MainActor (TaskListSnapshot) -> Void)?
    private(set) var isConnected = true

    func publish(_ snapshot: TaskListSnapshot) {
        published.append(snapshot)
        if isConnected {
            handler?(snapshot)
        }
    }

    func setSnapshotHandler(_ handler: @escaping @MainActor (TaskListSnapshot) -> Void) {
        self.handler = handler
        if isConnected, let last = published.last {
            handler(last)
        }
    }

    func disconnect() {
        isConnected = false
    }

    func reconnect() {
        isConnected = true
        if let last = published.last {
            handler?(last)
        }
    }

    func deliver(_ snapshot: TaskListSnapshot) {
        handler?(snapshot)
    }
}
