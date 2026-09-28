/// A test double for `TaskSnapshotTransport` that lets tests control delivery timing:
/// connect/disconnect, redeliver old snapshots or commands, and replay the latest snapshot
/// plus any queued commands on reconnect.
@MainActor
final class ControllableTaskTransport: TaskSnapshotTransport {
    private(set) var published: [TaskListSnapshot] = []   // only to drive redelivery, never asserted on
    private(set) var sentCommands: [TaskCommand] = []      // every command ever sent, for redelivery in tests
    private var snapshotHandler: (@MainActor (TaskListSnapshot) -> Void)?
    private var commandHandler: (@MainActor (TaskCommand) -> Void)?
    private(set) var isConnected = true
    private var queuedCommands: [TaskCommand] = []         // sent while disconnected or before a handler exists

    func publish(_ snapshot: TaskListSnapshot) {
        published.append(snapshot)
        if isConnected {
            snapshotHandler?(snapshot)
        }
    }

    func setSnapshotHandler(_ handler: @escaping @MainActor (TaskListSnapshot) -> Void) {
        snapshotHandler = handler
        if isConnected, let last = published.last {
            handler(last)
        }
    }

    func send(_ command: TaskCommand) {
        sentCommands.append(command)
        if isConnected, let commandHandler {
            commandHandler(command)
        } else {
            queuedCommands.append(command)
        }
    }

    func setCommandHandler(_ handler: @escaping @MainActor (TaskCommand) -> Void) {
        commandHandler = handler
        guard isConnected else { return }
        let queued = queuedCommands
        queuedCommands.removeAll()
        queued.forEach(handler)
    }

    func disconnect() {
        isConnected = false
    }

    func reconnect() {
        isConnected = true
        if let last = published.last {
            snapshotHandler?(last)
        }
        let queued = queuedCommands
        queuedCommands.removeAll()
        queued.forEach { command in
            if let commandHandler {
                commandHandler(command)
            } else {
                queuedCommands.append(command)
            }
        }
    }

    func deliver(_ snapshot: TaskListSnapshot) {
        snapshotHandler?(snapshot)
    }

    /// Redelivers an arbitrary earlier command (from `sentCommands`) to the current command
    /// handler, regardless of connection state. Used to simulate duplicate delivery.
    func redeliver(_ command: TaskCommand) {
        commandHandler?(command)
    }
}
