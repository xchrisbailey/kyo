/// A test double for `HabitSnapshotTransport` that lets tests control delivery timing:
/// connect/disconnect, redeliver old or arbitrary snapshots and commands, and queue commands
/// sent while disconnected.
@MainActor
final class ControllableHabitTransport: HabitSnapshotTransport {
    private(set) var published: [HabitListSnapshot] = []   // only to drive redelivery
    private(set) var sentCommands: [HabitCommand] = []      // every command ever sent, for redelivery in tests
    private var handler: (@MainActor (HabitListSnapshot) -> Void)?
    private var commandHandler: (@MainActor (HabitCommand) -> Void)?
    private(set) var isConnected = true
    private var queuedCommands: [HabitCommand] = []         // sent while disconnected or before a handler exists

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

    func send(_ command: HabitCommand) {
        sentCommands.append(command)
        if isConnected, let commandHandler {
            commandHandler(command)
        } else {
            queuedCommands.append(command)
        }
    }

    func setHabitCommandHandler(_ handler: @escaping @MainActor (HabitCommand) -> Void) {
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
            handler?(last)
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

    /// Delivers an arbitrary snapshot regardless of connection state (duplicate or stale delivery).
    func deliver(_ snapshot: HabitListSnapshot) {
        handler?(snapshot)
    }

    /// Redelivers an arbitrary earlier command (from `sentCommands`) to the current command
    /// handler, regardless of connection state. Used to simulate duplicate delivery.
    func redeliver(_ command: HabitCommand) {
        commandHandler?(command)
    }
}
