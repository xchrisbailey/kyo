import Foundation

/// A **Voice memo** the Watch has recorded and not yet had confirmed by the phone: the outbox
/// entry the Watch writes before it transfers the file, and the metadata that travels with it
/// (memo id, start time, the Watch's calendar day, duration). See
/// `docs/adr/0005-watch-memo-sync.md`.
///
/// The recording's file is named by `id` and lives next to the entry, on the Watch, until the
/// phone confirms the memo.
struct WatchRecordingEntry: Codable, Equatable, Sendable, Identifiable {
    /// Becomes the memo's id on the phone, so a repeat delivery is recognized.
    let id: UUID
    /// When the Watch started recording.
    let startedAt: Date
    /// The Watch's calendar day when it started recording. The memo belongs to this day, not to
    /// the day the phone receives it.
    let day: TaskCompletionDay
    /// Seconds of audio, not counting any pause.
    let duration: TimeInterval

    /// The `WCSession` metadata key. The entry travels as one JSON value so the dictionary holds
    /// only property-list types, which `transferFile` requires.
    static let metadataKey = "kyo.watchRecording"

    func metadata() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.metadataKey: data]
    }

    /// `nil` when `metadata` isn't a recording's.
    init?(metadata: [String: Any]?) {
        guard let data = metadata?[Self.metadataKey] as? Data,
              let entry = try? JSONDecoder().decode(WatchRecordingEntry.self, from: data)
        else { return nil }
        self = entry
    }

    init(id: UUID, startedAt: Date, day: TaskCompletionDay, duration: TimeInterval) {
        self.id = id
        self.startedAt = startedAt
        self.day = day
        self.duration = duration
    }
}

/// A recording as it arrives on the phone: where the system put the file, and what the Watch
/// said about it.
struct ReceivedWatchRecording: Equatable, Sendable {
    let file: URL
    let entry: WatchRecordingEntry
}

/// Carries Watch recordings to the phone as files (ADR 0005). The Watch's outbox sends through
/// it and the phone's memo store receives through it. The real one is
/// `WatchConnectivityTaskTransport`, over `WCSession.transferFile`, which doesn't work in the
/// Simulator; tests use a controllable one.
@MainActor
protocol MemoFileTransport: AnyObject {
    // MARK: Watch side

    /// Whether the session has activated. `transferFile` is a programmer error before then, so
    /// the outbox sends only once this is `true`.
    var isActivated: Bool { get }
    /// Registers the outbox's activation handler, called each time the session activates, and
    /// at once if it already has. The outbox sends everything unsent then.
    func setActivationHandler(_ handler: @escaping @MainActor () -> Void)
    /// Queues the recording's file for the phone, with `entry` as its metadata. Only while
    /// `isActivated`. Delivery doesn't need the phone to be reachable. The transport doesn't
    /// copy or delete `file`; the outbox owns it.
    func transferRecording(_ entry: WatchRecordingEntry, file: URL)
    /// The recordings queued for the phone and not yet delivered (`outstandingFileTransfers`).
    var outstandingRecordingIDs: Set<UUID> { get }
    /// Registers the handler for a transfer ending, with the error if it failed. A transfer that
    /// ends without an error isn't delivery: only the phone's confirmation is.
    func setTransferFinishedHandler(_ handler: @escaping @MainActor (_ id: UUID, _ error: (any Error)?) -> Void)

    // MARK: Phone side

    /// Registers the phone's receiver. The system deletes a received file when the receiver
    /// returns, so the receiver runs synchronously, on whichever thread the system calls it
    /// on, and must move the file before it returns. Recordings that arrived before this call
    /// are delivered to the receiver now.
    func setRecordingReceiver(_ receiver: @escaping @Sendable (ReceivedWatchRecording) -> Void)
}

/// Where the phone keeps a Watch recording from the moment it's moved out of the system's
/// inbox until its memo is saved: the audio as `<id>.caf` and the entry as `<id>.json`. A
/// recording left here by a quit or crash is picked up again at the next launch.
struct WatchRecordingInbox: Sendable {
    let directory: URL

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "WatchRecordings", directoryHint: .isDirectory)
    }

    init(directory: URL = WatchRecordingInbox.defaultDirectory) {
        self.directory = directory
    }

    /// Moves the received file in, synchronously, so it can be called from inside
    /// `session(_:didReceive:)`. Returns `false` when the file couldn't be kept, in which case
    /// nothing is acknowledged and the Watch sends it again. A recording that's already here
    /// (a repeat delivery) is kept once.
    @discardableResult
    func keep(_ received: ReceivedWatchRecording) -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // The note first, so a crash between the two leaves a note with no audio, which is
            // harmless, rather than audio with no note.
            try JSONEncoder().encode(received.entry).write(to: noteURL(received.entry.id), options: .atomic)
            let destination = audioURL(received.entry.id)
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: received.file, to: destination)
            }
            return true
        } catch {
            return false
        }
    }

    /// Recordings waiting for their memo, oldest first.
    func pending() -> [ReceivedWatchRecording] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var pending: [ReceivedWatchRecording] = []
        for url in urls where url.pathExtension == "json" {
            let audio = url.deletingPathExtension().appendingPathExtension("caf")
            // A note with no audio yet is a recording `keep` is still moving in; one the
            // Watch never confirms is sent again.
            guard FileManager.default.fileExists(atPath: audio.path),
                  let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(WatchRecordingEntry.self, from: data)
            else { continue }
            pending.append(ReceivedWatchRecording(file: audio, entry: entry))
        }
        return pending.sorted { $0.entry.startedAt < $1.entry.startedAt }
    }

    func remove(id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(id))
        try? FileManager.default.removeItem(at: noteURL(id))
    }

    private func audioURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).caf", directoryHint: .notDirectory)
    }

    private func noteURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }
}
