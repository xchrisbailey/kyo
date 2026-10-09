import Foundation
import WatchConnectivity
import os

/// Carries `TaskListSnapshot`s from the phone to the Watch over `WCSession`'s
/// `applicationContext`, which keeps only the latest value delivered — a natural fit for
/// "latest wins" full-list sync (see docs/adr/0001-phone-authoritative-task-snapshots.md) —
/// and `TaskCommand`s from the Watch to the phone over `transferUserInfo`, which queues
/// reliably and survives unreachability instead of dropping anything (see
/// docs/adr/0002-watch-commands-and-phone-reconciliation.md). Watch recordings travel the same
/// way as files over `transferFile` (see docs/adr/0005-watch-memo-sync.md).
@MainActor
final class WatchConnectivityTaskTransport: NSObject, TaskSnapshotTransport, HabitSnapshotTransport, MemoSnapshotTransport, ThemeIDTransport, MemoFileTransport, WCSessionDelegate {
    static let shared = WatchConnectivityTaskTransport()

    nonisolated static let snapshotKey = "kyo.taskSnapshot"
    nonisolated static let habitSnapshotKey = "kyo.habitSnapshot"
    nonisolated static let memoSnapshotKey = "kyo.memoSnapshot"
    /// The phone's theme id, as the UTF-8 bytes of the id string (see
    /// `docs/adr/0007-watch-follows-the-phone-theme.md`).
    nonisolated static let themeIDKey = "kyo.themeID"
    nonisolated static let commandKey = "kyo.taskCommand"
    nonisolated static let habitCommandKey = "kyo.habitCommand"

    private let session: WCSession?
    private let logger = Logger(subsystem: "computer.srcery.kyo", category: "watch-sync")
    /// Latest encoded payload per context key. `updateApplicationContext` replaces the whole
    /// dictionary, so all keys are always written together.
    private var outgoingContext = ApplicationContextEntries()
    private var latestIncoming: TaskListSnapshot?
    private var handler: (@MainActor (TaskListSnapshot) -> Void)?
    private var latestIncomingHabits: HabitListSnapshot?
    private var habitHandler: (@MainActor (HabitListSnapshot) -> Void)?
    private var latestIncomingMemos: MemoListSnapshot?
    private var memoHandler: (@MainActor (MemoListSnapshot) -> Void)?
    private var latestIncomingThemeID: String?
    private var themeIDHandler: (@MainActor (String) -> Void)?
    private var commandHandler: (@MainActor (TaskCommand) -> Void)?
    private var habitCommandHandler: (@MainActor (HabitCommand) -> Void)?
    /// Encoded commands of either kind, held until the session has activated.
    private var pendingOutgoingCommands: [OutgoingCommand] = []
    private var pendingIncomingCommands: [TaskCommand] = []
    private var pendingIncomingHabitCommands: [HabitCommand] = []
    private var activationHandler: (@MainActor () -> Void)?
    private var transferFinishedHandler: (@MainActor (UUID, (any Error)?) -> Void)?
    /// Receives files on the system's thread, so it isn't actor-isolated.
    private nonisolated let fileRelay = ReceivedFileRelay()

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

    /// Hands each received file to the phone's receiver on the thread the system calls on, before
    /// anything hops to the main actor, because the system deletes the file when
    /// `session(_:didReceive:)` returns. A file that arrives before there's a receiver (the
    /// session activates before the memo store exists) is moved to a hold folder first, and
    /// handed over when the receiver is registered, including after a relaunch.
    private final class ReceivedFileRelay: @unchecked Sendable {
        private let lock = NSLock()
        private var receiver: (@Sendable (ReceivedWatchRecording) -> Void)?
        private let hold = WatchRecordingInbox(
            directory: URL.applicationSupportDirectory.appending(path: "WatchRecordingHold", directoryHint: .isDirectory)
        )

        func handle(_ received: ReceivedWatchRecording) {
            let receiver = lock.withLock { self.receiver }
            if let receiver {
                receiver(received)
            } else {
                hold.keep(received)
            }
        }

        func setReceiver(_ receiver: @escaping @Sendable (ReceivedWatchRecording) -> Void) {
            lock.withLock { self.receiver = receiver }
            for held in hold.pending() {
                receiver(held)
                // The receiver has moved the audio out; this clears what's left.
                hold.remove(id: held.entry.id)
            }
        }
    }

    private override convenience init() {
        self.init(session: WCSession.isSupported() ? WCSession.default : nil)
    }

    /// A transport over `session`, which it takes as its delegate and activates. Tests pass `nil`
    /// to get one that records what it would send and sends nothing.
    init(session: WCSession?) {
        self.session = session
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// The context the next `updateApplicationContext` writes: the latest payload of every key.
    var latestContext: [String: Any] { outgoingContext.context }

    /// What a context carries, taken out on the system's thread so it can cross to the main actor.
    /// The two paths a context arrives by, the one waiting at launch and the one that arrives
    /// while the app runs, both build it, so a key is read the same way on both.
    struct ReceivedContext: Sendable {
        let taskData: Data?
        let habitData: Data?
        let memoData: Data?
        /// The theme id, or `nil` when the context has none or none that reads as an id.
        let themeID: String?

        init(_ context: [String: Any]) {
            taskData = context[WatchConnectivityTaskTransport.snapshotKey] as? Data
            habitData = context[WatchConnectivityTaskTransport.habitSnapshotKey] as? Data
            memoData = context[WatchConnectivityTaskTransport.memoSnapshotKey] as? Data
            themeID = (context[WatchConnectivityTaskTransport.themeIDKey] as? Data)
                .flatMap { String(data: $0, encoding: .utf8) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
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

    /// Publishes the memo snapshot under its own key, merged with the task and habit snapshots
    /// in one context write (see `docs/adr/0005-watch-memo-sync.md`).
    func publish(_ snapshot: MemoListSnapshot) {
        do {
            publishContextEntry(try JSONEncoder().encode(snapshot), forKey: Self.memoSnapshotKey)
            logger.log("published memo revision \(snapshot.revision) (\(snapshot.memos.count) memos)")
        } catch {
            logger.error("failed to encode memo snapshot: \(error.localizedDescription)")
        }
    }

    /// Publishes the theme id under its own key, merged with the three snapshots in one context
    /// write (see `docs/adr/0007-watch-follows-the-phone-theme.md`). Like a snapshot, the latest id
    /// is written again whenever the session activates or the Watch's state changes.
    func publish(themeID: String) {
        publishContextEntry(Data(themeID.utf8), forKey: Self.themeIDKey)
        logger.log("published theme \(themeID)")
    }

    func setThemeIDHandler(_ handler: @escaping @MainActor (String) -> Void) {
        themeIDHandler = handler
        if let latestIncomingThemeID {
            handler(latestIncomingThemeID)
        }
    }

    func setMemoSnapshotHandler(_ handler: @escaping @MainActor (MemoListSnapshot) -> Void) {
        memoHandler = handler
        if let latestIncomingMemos {
            handler(latestIncomingMemos)
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

    private func receiveMemos(data: Data) {
        guard let snapshot = try? JSONDecoder().decode(MemoListSnapshot.self, from: data) else { return }
        latestIncomingMemos = snapshot
        memoHandler?(snapshot)
        logger.log("received memo snapshot revision \(snapshot.revision) (\(snapshot.memos.count) memos)")
    }

    private func receiveThemeID(_ themeID: String) {
        latestIncomingThemeID = themeID
        themeIDHandler?(themeID)
        logger.log("received theme \(themeID)")
    }

    /// Applies what a context carries. A key the context lacks changes nothing.
    func receive(_ context: ReceivedContext) {
        if let taskData = context.taskData { receive(data: taskData) }
        if let habitData = context.habitData { receiveHabits(data: habitData) }
        if let memoData = context.memoData { receiveMemos(data: memoData) }
        if let themeID = context.themeID { receiveThemeID(themeID) }
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

    // MARK: - MemoFileTransport

    var isActivated: Bool {
        session?.activationState == .activated
    }

    /// Whether the session is activated and everything the counterpart sent has been delivered to
    /// the delegate: what a `WKWatchConnectivityRefreshBackgroundTask` waits for.
    var isActivatedWithNoPendingContent: Bool {
        guard let session else { return true }
        return session.activationState == .activated && !session.hasContentPending
    }

    func setActivationHandler(_ handler: @escaping @MainActor () -> Void) {
        activationHandler = handler
        if isActivated { handler() }
    }

    func transferRecording(_ entry: WatchRecordingEntry, file: URL) {
        guard let session, session.activationState == .activated else { return }
        session.transferFile(file, metadata: entry.metadata())
        logger.log("transferring recording \(entry.id)")
    }

    var outstandingRecordingIDs: Set<UUID> {
        Set((session?.outstandingFileTransfers ?? []).compactMap { WatchRecordingEntry(metadata: $0.file.metadata)?.id })
    }

    func setTransferFinishedHandler(_ handler: @escaping @MainActor (UUID, (any Error)?) -> Void) {
        transferFinishedHandler = handler
    }

    nonisolated func setRecordingReceiver(_ receiver: @escaping @Sendable (ReceivedWatchRecording) -> Void) {
        fileRelay.setReceiver(receiver)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let received = ReceivedContext(session.receivedApplicationContext)
        Task { @MainActor in
            self.sendLatest()
            self.flushPendingOutgoingCommands()
            self.receive(received)
            // After the received context, so a recording the phone has already confirmed is
            // retired before the outbox looks for what to send.
            if self.isActivated {
                self.activationHandler?()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let received = ReceivedContext(applicationContext)
        Task { @MainActor in
            self.receive(received)
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

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        guard let id = WatchRecordingEntry(metadata: fileTransfer.file.metadata)?.id else { return }
        Task { @MainActor in
            self.transferFinishedHandler?(id, error)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Not a recording of ours: the system deletes the file when this returns.
        guard let entry = WatchRecordingEntry(metadata: file.metadata) else { return }
        fileRelay.handle(ReceivedWatchRecording(file: file.fileURL, entry: entry))
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
