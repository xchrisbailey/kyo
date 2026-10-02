import Foundation

/// A test double for `MemoFileTransport` that lets tests control the file transfer: whether the
/// session has activated, whether the phone is reachable, when a transfer ends and how, and
/// duplicate or late delivery. Like the system, it deletes a received file as soon as the phone's
/// receiver returns, so a receiver that doesn't move the file synchronously loses it.
@MainActor
final class ControllableMemoFileTransport: MemoFileTransport {
    struct TransferFailure: Error {}

    /// One `transferRecording` call: the entry (the metadata) and the file's bytes as they were.
    struct Transfer {
        let entry: WatchRecordingEntry
        let data: Data
    }

    private(set) var isActivated: Bool
    private(set) var isConnected = true
    /// Every `transferRecording` call, in order.
    private(set) var transferCalls: [Transfer] = []
    /// Calls made before the session had activated, which `WCSession` calls a programmer error.
    private(set) var callsBeforeActivation = 0
    /// For each file the phone's receiver was given: whether it still existed once the receiver
    /// returned. `false` means the receiver moved it, as it must.
    private(set) var receivedFileSurvivedReceiver: [Bool] = []
    /// Runs as `transferRecording` is called, so a test can see what the Watch had stored by then.
    var onTransfer: ((WatchRecordingEntry, URL) -> Void)?

    private var activationHandler: (@MainActor () -> Void)?
    private var finishedHandler: (@MainActor (UUID, (any Error)?) -> Void)?
    private var receiver: (@Sendable (ReceivedWatchRecording) -> Void)?
    /// Queued with the system and not yet delivered.
    private var queued: [Transfer] = []

    init(isActivated: Bool = true) {
        self.isActivated = isActivated
    }

    // MARK: MemoFileTransport

    func setActivationHandler(_ handler: @escaping @MainActor () -> Void) {
        activationHandler = handler
        if isActivated { handler() }
    }

    func transferRecording(_ entry: WatchRecordingEntry, file: URL) {
        if !isActivated { callsBeforeActivation += 1 }
        onTransfer?(entry, file)
        let transfer = Transfer(entry: entry, data: (try? Data(contentsOf: file)) ?? Data())
        transferCalls.append(transfer)
        queued.append(transfer)
        deliverQueued()
    }

    var outstandingRecordingIDs: Set<UUID> {
        Set(queued.map(\.entry.id))
    }

    func setTransferFinishedHandler(_ handler: @escaping @MainActor (UUID, (any Error)?) -> Void) {
        finishedHandler = handler
    }

    func setRecordingReceiver(_ receiver: @escaping @Sendable (ReceivedWatchRecording) -> Void) {
        self.receiver = receiver
        deliverQueued()
    }

    // MARK: Controls

    /// The session activates (or activates again).
    func activate() {
        isActivated = true
        activationHandler?()
    }

    /// The phone can't be reached: transfers queue up and wait.
    func disconnect() {
        isConnected = false
    }

    func reconnect() {
        isConnected = true
        deliverQueued()
    }

    /// The transfer ends without an error, though the phone hasn't stored anything: what
    /// `didFinish` can mean.
    func finishWithoutDelivery(_ id: UUID) {
        guard queued.contains(where: { $0.entry.id == id }) else { return }
        queued.removeAll { $0.entry.id == id }
        finishedHandler?(id, nil)
    }

    /// The transfer ends with an error.
    func fail(_ id: UUID) {
        queued.removeAll { $0.entry.id == id }
        finishedHandler?(id, TransferFailure())
    }

    /// Delivers a recording the Watch already sent once more (a retry, or a late arrival).
    func deliverAgain(_ id: UUID) {
        guard let transfer = transferCalls.last(where: { $0.entry.id == id }) else { return }
        deliver(transfer)
    }

    /// Delivers a recording that has no Watch behind it, for tests of the phone alone.
    func deliver(_ entry: WatchRecordingEntry, data: Data = Data([0xC1, 0xC2, 0xC3])) {
        deliver(Transfer(entry: entry, data: data))
    }

    // MARK: Private

    private func deliverQueued() {
        guard isConnected, receiver != nil else { return }
        let waiting = queued
        queued.removeAll()
        for transfer in waiting {
            deliver(transfer)
            finishedHandler?(transfer.entry.id, nil)
        }
    }

    private func deliver(_ transfer: Transfer) {
        guard let receiver else { return }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(transfer.entry.id.uuidString).caf", directoryHint: .notDirectory)
        try? transfer.data.write(to: file)
        receiver(ReceivedWatchRecording(file: file, entry: transfer.entry))
        // What the system does when `session(_:didReceive:)` returns.
        receivedFileSurvivedReceiver.append(FileManager.default.fileExists(atPath: file.path))
        try? FileManager.default.removeItem(at: directory)
    }
}
