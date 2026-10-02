/// A test double for `MemoSnapshotTransport` that lets tests control delivery timing:
/// connect/disconnect, and redeliver old or arbitrary snapshots.
@MainActor
final class ControllableMemoTransport: MemoSnapshotTransport {
    private(set) var published: [MemoListSnapshot] = []
    private var handler: (@MainActor (MemoListSnapshot) -> Void)?
    private(set) var isConnected = true

    func publish(_ snapshot: MemoListSnapshot) {
        published.append(snapshot)
        if isConnected {
            handler?(snapshot)
        }
    }

    func setMemoSnapshotHandler(_ handler: @escaping @MainActor (MemoListSnapshot) -> Void) {
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
    func deliver(_ snapshot: MemoListSnapshot) {
        handler?(snapshot)
    }
}
