/// A test double for `HabitSnapshotTransport` that lets tests control delivery timing:
/// connect/disconnect and redeliver old or arbitrary snapshots.
@MainActor
final class ControllableHabitTransport: HabitSnapshotTransport {
    private(set) var published: [HabitListSnapshot] = []   // only to drive redelivery
    private var handler: (@MainActor (HabitListSnapshot) -> Void)?
    private(set) var isConnected = true

    func publish(_ snapshot: HabitListSnapshot) {
        published.append(snapshot)
        if isConnected {
            handler?(snapshot)
        }
    }

    func setHabitSnapshotHandler(_ handler: @escaping @MainActor (HabitListSnapshot) -> Void) {
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

    /// Delivers an arbitrary snapshot regardless of connection state (duplicate or stale delivery).
    func deliver(_ snapshot: HabitListSnapshot) {
        handler?(snapshot)
    }
}
