import Foundation

/// The Watch's recordings that the phone hasn't confirmed yet, and the files behind them (ADR
/// 0005). Each recording is written here before it's transferred: the audio as `<id>.caf` in
/// `directory` and an entry (memo id, start time, Watch day, duration) in `userDefaults`, so a
/// quit or crash can't lose it. It stays until the phone lists its id in the memo snapshot's
/// `acknowledgedMemoIDs`; a transfer finishing isn't delivery.
///
/// It's also where a finished recording is saved on the Watch, so `VoiceRecordingSession` can
/// record there as it does into the phone's memo store.
@MainActor
final class WatchRecordingOutbox: ObservableObject, VoiceMemoSaving {
    static let storageKey = "kyo.watchMemos.outbox.v1"

    /// Recordings not yet confirmed by the phone, oldest first.
    @Published private(set) var entries: [WatchRecordingEntry]

    /// A failed transfer is sent again at once, this many times in a row, then waits for the next
    /// launch or activation, so a transfer that always fails doesn't spin.
    static let maxImmediateRetries = 3

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let directory: URL
    private let calendar: Calendar
    private let transport: any MemoFileTransport
    private var failures: [UUID: Int] = [:]

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "WatchOutbox", directoryHint: .isDirectory)
    }

    /// `calendar` decides the Watch day a recording belongs to.
    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = WatchRecordingOutbox.storageKey,
        directory: URL = WatchRecordingOutbox.defaultDirectory,
        calendar: Calendar = .current,
        transport: any MemoFileTransport
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.directory = directory
        self.calendar = calendar
        self.transport = transport
        self.entries = userDefaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([WatchRecordingEntry].self, from: $0) } ?? []
        removeFilesWithNoEntry()
        transport.setTransferFinishedHandler { [weak self] id, error in
            self?.transferFinished(id: id, error: error)
        }
        // Registered last: the transport calls it at once if the session has already activated,
        // and the launch resend needs everything above in place.
        transport.setActivationHandler { [weak self] in
            self?.resendUnsent()
        }
    }

    // MARK: Saving

    /// Writes the recording and its entry, then sends it. The entry is written before the
    /// transfer starts. Throws `AudioRecordingError.outOfSpace` when the file can't be written,
    /// saving nothing. Saving the same recording again keeps one entry.
    @discardableResult
    func saveVoiceMemo(_ audio: RecordedAudio, stoppedAtCap: Bool, photos: [StoredPhoto]) throws -> Memo {
        let day = TaskCompletionDay(date: audio.startedAt, calendar: calendar)
        let entry = WatchRecordingEntry(id: audio.id, startedAt: audio.startedAt, day: day, duration: audio.duration)
        let memo = Memo(
            id: audio.id, kind: .voice, createdAt: audio.startedAt, day: day, text: "",
            duration: audio.duration, transcriptState: .transcribing, stoppedAtCap: stoppedAtCap
        )
        guard !entries.contains(where: { $0.id == audio.id }) else { return memo }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try audio.data.write(to: fileURL(for: audio.id), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: fileURL(for: audio.id))
            throw AudioRecordingError.outOfSpace
        }
        entries.append(entry)
        guard persist() else {
            entries.removeLast()
            try? FileManager.default.removeItem(at: fileURL(for: audio.id))
            throw AudioRecordingError.outOfSpace
        }
        send(entry)
        return memo
    }

    // MARK: Confirmation

    /// Retires the recordings the phone has confirmed: deletes their files and entries. Ids it
    /// doesn't know are ignored.
    func retire(acknowledged ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let confirmed = entries.filter { ids.contains($0.id) }
        guard !confirmed.isEmpty else { return }
        for entry in confirmed {
            try? FileManager.default.removeItem(at: fileURL(for: entry.id))
            failures[entry.id] = nil
        }
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    // MARK: Sending

    /// Sends every recording that isn't already queued with the transport: at launch, and each
    /// time the session activates.
    func resendUnsent() {
        failures.removeAll()
        for entry in entries {
            send(entry)
        }
    }

    private func send(_ entry: WatchRecordingEntry) {
        // Before the session activates, the entry waits here; the activation handler sends it.
        guard transport.isActivated else { return }
        guard !transport.outstandingRecordingIDs.contains(entry.id) else { return }
        let file = fileURL(for: entry.id)
        guard FileManager.default.fileExists(atPath: file.path) else {
            // The audio is gone, so there's nothing to send or wait for.
            retire(acknowledged: [entry.id])
            return
        }
        transport.transferRecording(entry, file: file)
    }

    /// A transfer that ended with an error is sent again. One that ended without is not treated
    /// as delivery: the file and entry stay until the phone confirms.
    private func transferFinished(id: UUID, error: (any Error)?) {
        guard error != nil, let entry = entries.first(where: { $0.id == id }) else { return }
        let count = failures[id, default: 0] + 1
        failures[id] = count
        guard count <= Self.maxImmediateRetries else { return }
        send(entry)
    }

    // MARK: Storage

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).caf", directoryHint: .notDirectory)
    }

    @discardableResult
    private func persist() -> Bool {
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        userDefaults.set(data, forKey: storageKey)
        return true
    }

    /// A quit between writing a file and its entry leaves a file nothing refers to. The recorder
    /// still has its own copy then, so the recording is saved again from there.
    private func removeFilesWithNoEntry() {
        let known = Set(entries.map(\.id))
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "caf" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), !known.contains(id) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
