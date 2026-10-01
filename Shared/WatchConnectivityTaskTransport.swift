import Foundation
import WatchConnectivity
import os

/// Carries `TaskListSnapshot`s from the phone to the Watch over `WCSession`'s
/// `applicationContext`, which keeps only the latest value delivered — a natural fit for
/// "latest wins" full-list sync (see docs/adr/0001-phone-authoritative-task-snapshots.md) —
/// and `TaskCommand`s from the Watch to the phone over `transferUserInfo`, which queues
/// reliably and survives unreachability instead of dropping anything (see
/// docs/adr/0002-watch-commands-and-phone-reconciliation.md).
@MainActor
final class WatchConnectivityTaskTransport: NSObject, TaskSnapshotTransport, HabitSnapshotTransport, WCSessionDelegate {
    static let shared = WatchConnectivityTaskTransport()

    nonisolated static let snapshotKey = "kyo.taskSnapshot"
    nonisolated static let habitSnapshotKey = "kyo.habitSnapshot"
    nonisolated static let commandKey = "kyo.taskCommand"
    nonisolated static let habitCommandKey = "kyo.habitCommand"

    private let session: WCSession?
    private let logger = Logger(subsystem: "com.example.kyo", category: "watch-sync")
    /// Latest encoded payload per context key. `updateApplicationContext` replaces the whole
    /// dictionary, so all keys are always written together.
    private var outgoingContext = ApplicationContextEntries()
    private var latestIncoming: TaskListSnapshot?
    private var handler: (@MainActor (TaskListSnapshot) -> Void)?
    private var latestIncomingHabits: HabitListSnapshot?
    private var habitHandler: (@MainActor (HabitListSnapshot) -> Void)?
    private var commandHandler: (@MainActor (TaskCommand) -> Void)?
    private var habitCommandHandler: (@MainActor (HabitCommand) -> Void)?
    /// Encoded commands of either kind, held until the session has activated.
    private var pendingOutgoingCommands: [OutgoingCommand] = []
    private var pendingIncomingCommands: [TaskCommand] = []
    private var pendingIncomingHabitCommands: [HabitCommand] = []

    /// A command already encoded for `transferUserInfo`, under the key for its kind.
    private struct OutgoingCommand {
        let key: String
        let id: UUID
        let data: Data
    }

    /// Reads just the `id` of an encoded command of either kind.
    private struct CommandIdentity: Decodable {
        let id: UUID
    }

    private override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func publish(_ snapshot: TaskListSnapshot) {
        do {
            publishContextEntry(try JSONEncoder().encode(snapshot), forKey: Self.snapshotKey)
            logger.log("published revision \(snapshot.revision) (\(snapshot.tasks.count) tasks)")
        } catch {
            logger.error("failed to encode snapshot: \(error.localizedDescription)")
        }
    }

    /// Publishes the habit snapshot under its own key, merged with the task snapshot in one
    /// context write (see `docs/adr/0003-habit-sync.md`).
    func publish(_ snapshot: HabitListSnapshot) {
        do {
            publishContextEntry(try JSONEncoder().encode(snapshot), forKey: Self.habitSnapshotKey)
            logger.log("published habit revision \(snapshot.revision) (\(snapshot.habits.count) habits)")
        } catch {
            logger.error("failed to encode habit snapshot: \(error.localizedDescription)")
        }
    }

    func setHabitSnapshotHandler(_ handler: @escaping @MainActor (HabitListSnapshot) -> Void) {
        habitHandler = handler
        if let latestIncomingHabits {
            handler(latestIncomingHabits)
        }
    }

    /// Records `data` as the latest payload for `key` and writes every key's latest payload in
    /// one application-context update, so publishing one snapshot kind never erases another.
    /// Other snapshot kinds (e.g. habits) publish through here.
    func publishContextEntry(_ data: Data, forKey key: String) {
        outgoingContext.set(data, forKey: key)
        sendLatest()
    }

    func setSnapshotHandler(_ handler: @escaping @MainActor (TaskListSnapshot) -> Void) {
        self.handler = handler
        if let latestIncoming {
            handler(latestIncoming)
        }
    }

    /// Queues `command` for delivery via `transferUserInfo`, which — unlike
    /// `applicationContext` — survives the counterpart being unreachable and never drops a
    /// command. Buffers locally until the session has activated.
    func send(_ command: TaskCommand) {
        enqueue(command, id: command.id, key: Self.commandKey)
    }

    /// Queues a habit command exactly like a task command, under its own userInfo key.
    func send(_ command: HabitCommand) {
        enqueue(command, id: command.id, key: Self.habitCommandKey)
    }

    func setCommandHandler(_ handler: @escaping @MainActor (TaskCommand) -> Void) {
        commandHandler = handler
        let queued = pendingIncomingCommands
        pendingIncomingCommands.removeAll()
        queued.forEach(handler)
    }

    func setHabitCommandHandler(_ handler: @escaping @MainActor (HabitCommand) -> Void) {
        habitCommandHandler = handler
        let queued = pendingIncomingHabitCommands
        pendingIncomingHabitCommands.removeAll()
        queued.forEach(handler)
    }

    private func enqueue<Command: Encodable>(_ command: Command, id: UUID, key: String) {
        let data: Data
        do {
            data = try JSONEncoder().encode(command)
        } catch {
            logger.error("failed to encode command: \(error.localizedDescription)")
            return
        }
        let outgoing = OutgoingCommand(key: key, id: id, data: data)
        guard let session, session.activationState == .activated else {
            pendingOutgoingCommands.append(outgoing)
            return
        }
        transfer(outgoing, over: session)
    }

    private func transfer(_ command: OutgoingCommand, over session: WCSession) {
        // Cancel any outstanding transfer already carrying this command id so a retry (e.g.
        // resending the outbox on Watch restart) doesn't pile up duplicate transfers.
        for outstanding in session.outstandingUserInfoTransfers {
            guard let data = outstanding.userInfo[command.key] as? Data,
                  let queued = try? JSONDecoder().decode(CommandIdentity.self, from: data),
                  queued.id == command.id else { continue }
            outstanding.cancel()
        }
        session.transferUserInfo([command.key: command.data])
        logger.log("sent command \(command.id)")
    }

    private func flushPendingOutgoingCommands() {
        guard let session, session.activationState == .activated, !pendingOutgoingCommands.isEmpty else { return }
        let queued = pendingOutgoingCommands
        pendingOutgoingCommands.removeAll()
        for command in queued {
            transfer(command, over: session)
        }
    }

    private func sendLatest() {
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard !outgoingContext.isEmpty else { return }
        do {
            try session.updateApplicationContext(outgoingContext.context)
        } catch {
            logger.error("failed to update application context: \(error.localizedDescription)")
        }
    }

    private func receive(data: Data) {
        guard let snapshot = try? JSONDecoder().decode(TaskListSnapshot.self, from: data) else { return }
        latestIncoming = snapshot
        handler?(snapshot)
        logger.log("received snapshot revision \(snapshot.revision) (\(snapshot.tasks.count) tasks)")
    }

    private func receiveHabits(data: Data) {
        guard let snapshot = try? JSONDecoder().decode(HabitListSnapshot.self, from: data) else { return }
        latestIncomingHabits = snapshot
        habitHandler?(snapshot)
        logger.log("received habit snapshot revision \(snapshot.revision) (\(snapshot.habits.count) habits)")
    }

    private func receiveCommand(data: Data) {
        guard let command = try? JSONDecoder().decode(TaskCommand.self, from: data) else { return }
        if let commandHandler {
            commandHandler(command)
        } else {
            pendingIncomingCommands.append(command)
        }
        logger.log("received command \(command.id)")
    }

    private func receiveHabitCommand(data: Data) {
        guard let command = try? JSONDecoder().decode(HabitCommand.self, from: data) else { return }
        if let habitCommandHandler {
            habitCommandHandler(command)
        } else {
            pendingIncomingHabitCommands.append(command)
        }
        logger.log("received habit command \(command.id)")
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let contextData = session.receivedApplicationContext[Self.snapshotKey] as? Data
        let habitData = session.receivedApplicationContext[Self.habitSnapshotKey] as? Data
        Task { @MainActor in
            self.sendLatest()
            self.flushPendingOutgoingCommands()
            if let contextData {
                self.receive(data: contextData)
            }
            if let habitData {
                self.receiveHabits(data: habitData)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let taskData = applicationContext[Self.snapshotKey] as? Data
        let habitData = applicationContext[Self.habitSnapshotKey] as? Data
        Task { @MainActor in
            if let taskData { self.receive(data: taskData) }
            if let habitData { self.receiveHabits(data: habitData) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let taskData = userInfo[Self.commandKey] as? Data
        let habitData = userInfo[Self.habitCommandKey] as? Data
        Task { @MainActor in
            if let taskData { self.receiveCommand(data: taskData) }
            if let habitData { self.receiveHabitCommand(data: habitData) }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.sendLatest()
        }
    }
    #endif
}
