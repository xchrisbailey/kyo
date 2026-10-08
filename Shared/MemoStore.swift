import Combine
import Foundation
import SwiftData

/// What the views consume to capture and show **Memos**. Today's memos are listed newest
/// first. A memo belongs to the local calendar day it was created and never moves.
@MainActor
protocol MemoStoreBehavior: AnyObject, VoiceMemoSaving {
    /// Only the memos whose day is Today, newest first.
    var memos: [Memo] { get }
    /// "2 memos" (or "1 memo") when Today has memos, "Notes & voice" when it has none.
    var sectionSubtitle: String { get }

    /// `true` when any memo exists, on any day: whether **See all** shows.
    var hasMemos: Bool { get }

    /// Any memo, from any day, by id.
    func memo(id: UUID) -> Memo?
    /// The local days from `first` through `last` (any moment of each) that have at least one
    /// memo, each as that day's start. Reads no text, photos or audio.
    func daysWithMemos(from first: Date, through last: Date) -> Set<Date>
    /// The Memos sheet's content: memos grouped by local calendar day, newest day first (Today,
    /// then **Memo history**) and newest first within a day, up to `limit` memos. A non-empty
    /// `query` keeps the memos whose title, written text or transcript contains it, ignoring
    /// case and accents and matching part of a word; photos aren't searched. A match deep in
    /// the text carries a snippet. Reads text only, never photo or audio bytes.
    func memoGroups(matching query: String, limit: Int) -> MemoGroupsPage
    /// Saves a Written memo on Today, with up to 4 photos (any beyond that are dropped). A memo
    /// with no text and no photos is discarded: returns `nil`. With photos and no text it's a
    /// photo-only memo, titled "Photo memo".
    @discardableResult func addWrittenMemo(text: String, photos: [StoredPhoto]) -> Memo?
    /// Saves a Voice memo as soon as recording stops, on the day recording started, in
    /// Transcribing, and starts transcribing it. Up to 4 photos taken while recording go with
    /// it. Saving the same recording again returns the memo already saved.
    @discardableResult func addVoiceMemo(_ audio: RecordedAudio, stoppedAtCap: Bool, photos: [StoredPhoto]) -> Memo
    /// Attaches a photo to a memo, written or voice, after the ones it has. Returns `nil` and
    /// attaches nothing when the memo is unknown or already has 4 photos. Attaching a photo
    /// already attached changes nothing.
    @discardableResult func addPhoto(_ photo: StoredPhoto, toMemoID id: UUID) -> Memo?
    /// Removes one photo from a memo, for good. Removing the last photo of a memo with no text
    /// leaves it until it's closed, like emptying its text.
    @discardableResult func removePhoto(id photoID: UUID, fromMemoID id: UUID) -> Memo?
    /// A photo's stored HEIC, or `nil` for an unknown id. Reads the photo bytes, so only the open
    /// memo uses it.
    func photoData(forPhotoID id: UUID) -> Data?
    /// A photo's small thumbnail, or `nil` for an unknown id. Never reads the photo bytes.
    func thumbnailData(forPhotoID id: UUID) -> Data?
    /// Renames a Voice memo: the user's title is kept from now on, and a generated title never
    /// replaces it, even one still being generated. A blank name goes back to showing "Voice
    /// memo". A Written memo's title is its first line, so it can't be renamed: returns `nil`.
    @discardableResult func renameMemo(id: UUID, title: String) -> Memo?
    /// Saves new text immediately (a Voice memo's text is its Transcript). Emptying a Written
    /// memo's text keeps the memo until it's closed.
    @discardableResult func editMemo(id: UUID, text: String) -> Memo?
    /// Called when a memo's card closes. Discards a Written memo with no text and no photos,
    /// returning it. A Voice memo, and a Written memo with photos, are never discarded this way.
    @discardableResult func closeMemo(id: UUID) -> Memo?
    /// Permanent: no undo and no trash. Removes a Voice memo's audio and every photo too.
    @discardableResult func deleteMemo(id: UUID) -> Memo?

    /// A Voice memo's stored audio, or `nil` for a Written memo or an unknown id.
    func audioData(forMemoID id: UUID) -> Data?
    /// **Try again** on a Voice memo with No transcript: transcribes it again.
    @discardableResult func retryTranscription(id: UUID) -> Memo?
    /// Transcribes again, in the background, every Voice memo that is No transcript because the
    /// speech model wasn't installed. Called when it may be by now: at launch, when Kyo comes
    /// to the front, and when the transcriber reports readiness. The memo keeps showing No
    /// transcript until a transcript arrives.
    func retryTranscriptionsWaitingForModel()
    /// Transcribes again, in the background, every Voice memo that is No transcript because the
    /// device language wasn't supported and the language has changed since. Called at launch
    /// and when the device language changes.
    func retryTranscriptionsAfterLocaleChange()
}

extension MemoStoreBehavior {
    @discardableResult
    func addWrittenMemo(text: String) -> Memo? {
        addWrittenMemo(text: text, photos: [])
    }

    @discardableResult
    func addVoiceMemo(_ audio: RecordedAudio, stoppedAtCap: Bool) -> Memo {
        addVoiceMemo(audio, stoppedAtCap: stoppedAtCap, photos: [])
    }
}

@MainActor
final class MemoStore: ObservableObject, MemoStoreBehavior {
    @Published private(set) var memos: [Memo] = []
    @Published private(set) var hasMemos = false
    /// Counts every re-read of the saved memos, so a view that lists more than Today (the Memos
    /// sheet) knows to load again after any change.
    @Published private(set) var revision = 0
    @Published private(set) var currentDate: Date

    /// Held so the container, and with it the context, outlives every use of the store.
    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let now: () -> Date
    private let calendar: Calendar
    private let transcriber: any VoiceTranscriber
    private let languageModel: any OnDeviceLanguageModel

    /// Where today's memos are published for the Watch, or `nil` when nothing is (ADR 0005).
    private let memoSync: (any MemoSnapshotTransport)?
    private let userDefaults: UserDefaults
    private var memoSyncRevision: Int64?
    /// What was last published, so a refresh that changed nothing the Watch shows publishes nothing.
    private var lastPublishedWatchMemos: [WatchMemo]?
    private var lastPublishedAcknowledgedMemoIDs: [UUID]?
    static let memoSyncRevisionKey = "kyo.memos.syncRevision"

    /// Where Watch recordings arrive (ADR 0005), or `nil` when none do. The inbox keeps a
    /// recording from the moment it's moved out of the system's own until its memo is saved.
    private let watchRecordings: (any MemoFileTransport)?
    private let watchInbox: WatchRecordingInbox
    /// The ids of the Watch recordings already received, newest last, bounded. Published as
    /// `acknowledgedMemoIDs`, so the Watch can retire them. A repeat delivery of one is ignored
    /// but still acknowledged, which keeps a memo the user deleted from coming back. This is a
    /// Watch-link record, so it lives in `userDefaults`, not SwiftData (ADR 0004).
    private var receivedWatchRecordingIDs: [UUID]
    static let receivedWatchRecordingIDsKey = "kyo.memos.receivedWatchRecordings"
    /// The ids kept; older ones are forgotten, like the processed command ids.
    static let maxReceivedWatchRecordingIDs = 500

    /// A transcription waiting to run. A visible one shows Transcribing (a new recording, an
    /// arrival from the Watch, **Try again**); a background one retries a No transcript memo by
    /// itself and shows nothing until it produces a transcript.
    private struct Attempt {
        let id: UUID
        var isVisible: Bool
        /// The one automatic retry after an analysis error: it doesn't schedule another.
        var isErrorRetry = false
    }

    private let deviceLocale: () -> String
    private var pendingTranscriptions: [Attempt] = []
    private var runningTranscriptionID: UUID?
    private var transcriptionTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?
    private var localeTask: Task<Void, Never>?

    /// A title waiting to be generated, from the Transcript as it was when first finalized.
    private struct TitleRequest {
        let id: UUID
        let transcript: String
    }

    private var pendingTitles: [TitleRequest] = []
    private var titleTask: Task<Void, Never>?

    /// With `watchRecordings` the store takes in the Watch's recordings, moving each file into
    /// `watchInbox` as it arrives, and acknowledges them in the published memo snapshot.
    ///
    /// `now` and `calendar` make the current day controllable. A memo's day is taken from them
    /// when it's created and then kept. The `transcriber` fills in Voice memo Transcripts, one
    /// at a time. The `languageModel` generates a Voice memo's title, once, when its Transcript is
    /// first finalized. `deviceLocale` is the device language as a locale identifier. With a
    /// `memoSync` transport the store publishes today's memos for the Watch whenever they change,
    /// keeping the snapshot revision in `userDefaults`.
    init(
        modelContainer: ModelContainer,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        transcriber: any VoiceTranscriber = NoTranscriber(),
        languageModel: any OnDeviceLanguageModel = NoLanguageModel(),
        deviceLocale: @escaping () -> String = { Locale.current.identifier },
        memoSync: (any MemoSnapshotTransport)? = nil,
        watchRecordings: (any MemoFileTransport)? = nil,
        watchInbox: WatchRecordingInbox = WatchRecordingInbox(),
        userDefaults: UserDefaults = .standard
    ) {
        self.modelContainer = modelContainer
        self.context = modelContainer.mainContext
        self.now = now
        self.calendar = calendar
        self.transcriber = transcriber
        self.languageModel = languageModel
        self.deviceLocale = deviceLocale
        self.memoSync = memoSync
        self.userDefaults = userDefaults
        self.watchRecordings = watchRecordings
        self.watchInbox = watchInbox
        self.receivedWatchRecordingIDs = userDefaults.data(forKey: Self.receivedWatchRecordingIDsKey)
            .flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        self.memoSyncRevision = memoSync == nil
            ? nil : (userDefaults.object(forKey: Self.memoSyncRevisionKey) as? NSNumber)?.int64Value
        self.currentDate = calendar.startOfDay(for: now())
        discardEmptyWrittenMemos()
        refreshForCurrentDay()
        resumeInterruptedTranscriptions()
        retryTranscriptionsAtLaunch()
        watchTranscriberReadiness()
        watchDeviceLocale()
        receiveWatchRecordings()
    }

    var sectionSubtitle: String {
        switch memos.count {
        case 0: "Notes & voice"
        case 1: "1 memo"
        case let count: "\(count) memos"
        }
    }

    func memo(id: UUID) -> Memo? {
        records(withID: id).first?.memo
    }

    func daysWithMemos(from first: Date, through last: Date) -> Set<Date> {
        let lower = Self.dayKey(TaskCompletionDay(date: first, calendar: calendar))
        let upper = Self.dayKey(TaskCompletionDay(date: last, calendar: calendar))
        guard lower <= upper else { return [] }
        let descriptor = FetchDescriptor<MemoRecord>(
            predicate: #Predicate { $0.dayYear * 10_000 + $0.dayMonth * 100 + $0.dayDay >= lower && $0.dayYear * 10_000 + $0.dayMonth * 100 + $0.dayDay <= upper }
        )
        let days = ((try? context.fetch(descriptor)) ?? []).map(\.day)
        return Set(days.compactMap { day in
            calendar.date(from: DateComponents(era: day.era, year: day.year, month: day.month, day: day.day)).map(calendar.startOfDay(for:))
        })
    }

    func memoGroups(matching query: String, limit: Int) -> MemoGroupsPage {
        let term = MemoSearch.term(query)
        let sort = [
            SortDescriptor(\MemoRecord.dayYear, order: .reverse),
            SortDescriptor(\MemoRecord.dayMonth, order: .reverse),
            SortDescriptor(\MemoRecord.dayDay, order: .reverse),
            SortDescriptor(\MemoRecord.createdAt, order: .reverse),
        ]
        // `text` is a Written memo's text or a Voice memo's Transcript, and `title` a Voice
        // memo's stored title. A Written memo's title is its first line, so `text` covers it, and
        // the "Voice memo" fallback is stored as empty, so it's never matched.
        var descriptor = term.isEmpty
            ? FetchDescriptor<MemoRecord>(sortBy: sort)
            : FetchDescriptor<MemoRecord>(
                predicate: #Predicate { $0.text.localizedStandardContains(term) || $0.title.localizedStandardContains(term) },
                sortBy: sort
            )
        // One more than asked for tells whether there is another page.
        descriptor.fetchLimit = max(limit, 0) + 1
        let fetched = (try? context.fetch(descriptor)) ?? []
        let hasMore = fetched.count > limit
        let memos = uniqueByID(Array(fetched.prefix(max(limit, 0)))).map(\.memo).sorted(by: Self.isNewerDayFirst)

        let today = TaskCompletionDay(date: now(), calendar: calendar)
        var groups: [MemoDayGroup] = []
        var current: (day: TaskCompletionDay, results: [MemoSearchResult])?
        func closeGroup() {
            guard let current else { return }
            groups.append(MemoDayGroup(
                day: current.day,
                title: MemoDayHeader.title(for: current.day, today: today, calendar: calendar),
                results: current.results
            ))
        }
        for memo in memos {
            let result = MemoSearchResult(memo: memo, snippet: term.isEmpty ? nil : MemoSearch.snippet(for: memo, query: term))
            if current?.day == memo.day {
                current?.results.append(result)
            } else {
                closeGroup()
                current = (memo.day, [result])
            }
        }
        closeGroup()
        return MemoGroupsPage(query: term, groups: groups, hasMore: hasMore)
    }

    @discardableResult
    func addWrittenMemo(text: String, photos: [StoredPhoto]) -> Memo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !photos.isEmpty else { return nil }
        let createdAt = now()
        let record = MemoRecord(
            kind: .written,
            createdAt: createdAt,
            day: TaskCompletionDay(date: createdAt, calendar: calendar),
            text: trimmed
        )
        context.insert(record)
        attach(photos, to: record)
        save()
        refreshForCurrentDay()
        return record.memo
    }

    @discardableResult
    func addVoiceMemo(_ audio: RecordedAudio, stoppedAtCap: Bool, photos: [StoredPhoto]) -> Memo {
        insertVoiceMemo(
            audio, day: TaskCompletionDay(date: audio.startedAt, calendar: calendar),
            stoppedAtCap: stoppedAtCap, photos: photos, fromWatch: false
        )
    }

    /// Saves a Voice memo as soon as it's recorded, in Transcribing, and starts transcribing it.
    /// The recording's id is the memo's id, so saving a recording twice keeps one memo. A Watch
    /// recording is also recorded as received, before the snapshot that acknowledges it is
    /// published.
    @discardableResult
    private func insertVoiceMemo(
        _ audio: RecordedAudio, day: TaskCompletionDay, stoppedAtCap: Bool, photos: [StoredPhoto], fromWatch: Bool
    ) -> Memo {
        if let existing = records(withID: audio.id).first {
            if fromWatch {
                recordReceivedWatchRecording(audio.id)
                refreshForCurrentDay()
            }
            return existing.memo
        }
        let record = MemoRecord(
            id: audio.id,
            kind: .voice,
            createdAt: audio.startedAt,
            day: day,
            text: "",
            durationSeconds: audio.duration,
            transcriptState: .transcribing,
            stoppedAtCap: stoppedAtCap
        )
        record.audio = MemoAudioRecord(data: audio.data)
        context.insert(record)
        attach(photos, to: record)
        save()
        if fromWatch { recordReceivedWatchRecording(audio.id) }
        refreshForCurrentDay()
        enqueueTranscription(Attempt(id: audio.id, isVisible: true))
        return record.memo
    }

    // MARK: Watch recordings

    /// Starts receiving Watch recordings and takes in any a quit or crash left in the inbox.
    private func receiveWatchRecordings() {
        guard let watchRecordings else { return }
        let inbox = watchInbox
        // The system deletes the file when this returns, so it's moved here, on the system's
        // thread, and only then handed to the main actor.
        watchRecordings.setRecordingReceiver { [weak self] received in
            guard inbox.keep(received) else { return }
            Task { @MainActor in self?.takeInWatchRecordings() }
        }
        takeInWatchRecordings()
    }

    /// Makes a memo of every recording in the inbox, as Transcribing, on the day the Watch
    /// started it. A recording already received is dropped without a memo, so a memo deleted
    /// since doesn't come back, and acknowledged again.
    private func takeInWatchRecordings() {
        for received in watchInbox.pending() {
            let entry = received.entry
            if receivedWatchRecordingIDs.contains(entry.id) {
                watchInbox.remove(id: entry.id)
                // The Watch is still sending it, so it hasn't seen the acknowledgment: say it again.
                publishMemosForWatchIfChanged(force: true)
                continue
            }
            guard let data = try? Data(contentsOf: received.file) else {
                // Unreadable: nothing to save, and nothing is acknowledged, so the Watch sends it again.
                watchInbox.remove(id: entry.id)
                continue
            }
            insertVoiceMemo(
                RecordedAudio(id: entry.id, startedAt: entry.startedAt, duration: entry.duration, data: data),
                day: entry.day,
                // The Watch stops at the same 10-minute cap as the phone.
                stoppedAtCap: entry.duration >= VoiceRecordingSession.cap,
                photos: [], fromWatch: true
            )
            watchInbox.remove(id: entry.id)
        }
    }

    private func recordReceivedWatchRecording(_ id: UUID) {
        guard !receivedWatchRecordingIDs.contains(id) else { return }
        receivedWatchRecordingIDs.append(id)
        if receivedWatchRecordingIDs.count > Self.maxReceivedWatchRecordingIDs {
            receivedWatchRecordingIDs.removeFirst(receivedWatchRecordingIDs.count - Self.maxReceivedWatchRecordingIDs)
        }
        if let data = try? JSONEncoder().encode(receivedWatchRecordingIDs) {
            userDefaults.set(data, forKey: Self.receivedWatchRecordingIDsKey)
        }
    }

    @discardableResult
    func addPhoto(_ photo: StoredPhoto, toMemoID id: UUID) -> Memo? {
        guard let record = records(withID: id).first else { return nil }
        if record.orderedPhotos.contains(where: { $0.id == photo.id }) { return record.memo }
        guard record.orderedPhotos.count < Memo.maximumPhotos else { return nil }
        attach([photo], to: record)
        save()
        refreshForCurrentDay()
        return record.memo
    }

    @discardableResult
    func removePhoto(id photoID: UUID, fromMemoID id: UUID) -> Memo? {
        guard let record = records(withID: id).first,
              let photo = record.orderedPhotos.first(where: { $0.id == photoID })
        else { return nil }
        record.photos?.removeAll { $0.id == photoID }
        context.delete(photo)
        save()
        refreshForCurrentDay()
        return record.memo
    }

    func photoData(forPhotoID id: UUID) -> Data? {
        photoRecord(withID: id)?.data
    }

    func thumbnailData(forPhotoID id: UUID) -> Data? {
        var descriptor = FetchDescriptor<MemoPhotoRecord>(predicate: #Predicate { $0.id == id })
        // Only the small columns: the photo bytes stay on disk.
        descriptor.propertiesToFetch = [\.id, \.thumbnail]
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.thumbnail
    }

    func audioData(forMemoID id: UUID) -> Data? {
        records(withID: id).first?.audio?.data
    }

    @discardableResult
    func retryTranscription(id: UUID) -> Memo? {
        guard let record = records(withID: id).first, record.kind == .voice else { return nil }
        if record.transcriptState == .noTranscript {
            beginTranscribing(record)
        }
        return record.memo
    }

    func retryTranscriptionsWaitingForModel() {
        for record in noTranscriptRecords(retry: .whenModelReady) {
            enqueueTranscription(Attempt(id: record.id, isVisible: false))
        }
    }

    func retryTranscriptionsAfterLocaleChange() {
        let current = deviceLocale()
        for record in noTranscriptRecords(retry: .onLocaleChange) where record.transcriptLocaleIdentifier != current {
            enqueueTranscription(Attempt(id: record.id, isVisible: false))
        }
    }

    /// Returns once every transcription, and every title it led to, has finished. For tests.
    func transcriptionsSettled() async {
        while let task = transcriptionTask ?? titleTask {
            await task.value
        }
    }

    @discardableResult
    func renameMemo(id: UUID, title: String) -> Memo? {
        guard let record = records(withID: id).first, record.kind == .voice else { return nil }
        let name = Self.singleLine(title)
        if record.title != name || !record.titleIsUserSet {
            record.title = name
            record.titleIsUserSet = true
            save()
            refreshForCurrentDay()
        }
        return record.memo
    }

    @discardableResult
    func editMemo(id: UUID, text: String) -> Memo? {
        guard let record = records(withID: id).first else { return nil }
        // Whitespace-only text is stored as empty, so "no text" is a single stored state.
        let stored = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        if record.text != stored {
            record.text = stored
            save()
            refreshForCurrentDay()
        }
        return record.memo
    }

    @discardableResult
    func closeMemo(id: UUID) -> Memo? {
        guard let record = records(withID: id).first, record.kind == .written,
              record.text.isEmpty, record.orderedPhotos.isEmpty
        else { return nil }
        return deleteMemo(id: id)
    }

    @discardableResult
    func deleteMemo(id: UUID) -> Memo? {
        let matches = records(withID: id)
        guard let first = matches.first else { return nil }
        let removed = first.memo
        for record in matches {
            deleteIncludingMedia(record)
        }
        save()
        refreshForCurrentDay()
        return removed
    }

    /// Re-reads which saved memos belong to the local current day.
    func refreshForCurrentDay() {
        let moment = now()
        currentDate = calendar.startOfDay(for: moment)
        let today = TaskCompletionDay(date: moment, calendar: calendar)
        let year = today.year
        let month = today.month
        let day = today.day
        let descriptor = FetchDescriptor<MemoRecord>(
            predicate: #Predicate { $0.dayYear == year && $0.dayMonth == month && $0.dayDay == day }
        )
        let fetched = ((try? context.fetch(descriptor)) ?? []).filter { $0.dayEra == today.era }
        memos = uniqueByID(fetched).map(\.memo).sorted(by: Self.isNewer)
        revision &+= 1
        hasMemos = ((try? context.fetchCount(FetchDescriptor<MemoRecord>())) ?? 0) > 0
        publishMemosForWatchIfChanged()
    }

    /// Publishes today's memos to the Watch when what a Watch row shows has changed, and the
    /// first time. Every change and every day rollover comes through `refreshForCurrentDay`, so
    /// this covers both. The revision follows ADR 0001's hybrid clock.
    private func publishMemosForWatchIfChanged(force: Bool = false) {
        guard let memoSync else { return }
        let watchMemos = memos.map(WatchMemo.init)
        let acknowledged = receivedWatchRecordingIDs
        guard force || watchMemos != lastPublishedWatchMemos || acknowledged != lastPublishedAcknowledgedMemoIDs else { return }
        lastPublishedWatchMemos = watchMemos
        lastPublishedAcknowledgedMemoIDs = acknowledged
        let candidate = max((memoSyncRevision ?? 0) + 1, Int64(now().timeIntervalSince1970 * 1000))
        memoSyncRevision = candidate
        userDefaults.set(NSNumber(value: candidate), forKey: Self.memoSyncRevisionKey)
        memoSync.publish(MemoListSnapshot(revision: candidate, memos: watchMemos, acknowledgedMemoIDs: acknowledged))
    }

    /// Refreshes for the current day now, then again at every local midnight until cancelled.
    func refreshAtEachDayBoundary() async {
        while !Task.isCancelled {
            refreshForCurrentDay()
            let today = calendar.startOfDay(for: now())
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
            let delay = max(1, tomorrow.timeIntervalSince(now()))
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    // MARK: Storage

    /// Every record with `id`. The schema has no unique constraint, so a second record with the
    /// same id is possible; callers act on the first and `deleteMemo` removes them all.
    private func records(withID id: UUID) -> [MemoRecord] {
        let descriptor = FetchDescriptor<MemoRecord>(predicate: #Predicate { $0.id == id })
        return Self.keepOrder((try? context.fetch(descriptor)) ?? [])
    }

    private func photoRecord(withID id: UUID) -> MemoPhotoRecord? {
        var descriptor = FetchDescriptor<MemoPhotoRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Adds `photos` after the ones `record` has, up to the limit of 4.
    private func attach(_ photos: [StoredPhoto], to record: MemoRecord) {
        var taken = Set(record.orderedPhotos.map(\.id))
        var next = (record.orderedPhotos.map(\.order).max() ?? -1) + 1
        for photo in photos {
            guard taken.count < Memo.maximumPhotos else { break }
            guard taken.insert(photo.id).inserted else { continue }
            let stored = MemoPhotoRecord(id: photo.id, order: next, data: photo.data, thumbnail: photo.thumbnail)
            context.insert(stored)
            stored.memo = record
            next += 1
        }
    }

    /// A Written memo emptied while its card was open, then left behind by a quit, is discarded
    /// on the next launch: a Written memo with no text and no photos is never kept. Only Written
    /// memos are judged by their text; a Voice memo, and a photo-only memo, legitimately have none.
    private func discardEmptyWrittenMemos() {
        let written = Memo.Kind.written.rawValue
        let descriptor = FetchDescriptor<MemoRecord>(predicate: #Predicate { $0.kindRaw == written && $0.text == "" })
        for record in (try? context.fetch(descriptor)) ?? [] where record.orderedPhotos.isEmpty {
            deleteIncludingMedia(record)
        }
        save()
    }

    private func deleteIncludingMedia(_ record: MemoRecord) {
        if let audio = record.audio {
            context.delete(audio)
        }
        for photo in record.photos ?? [] {
            context.delete(photo)
        }
        context.delete(record)
    }

    // MARK: Transcription

    /// A quit that interrupted a transcription leaves its memo in Transcribing; it starts again.
    private func resumeInterruptedTranscriptions() {
        let voice = Memo.Kind.voice.rawValue
        let transcribing = Memo.TranscriptState.transcribing.rawValue
        let descriptor = FetchDescriptor<MemoRecord>(
            predicate: #Predicate { $0.kindRaw == voice && $0.transcriptStateRaw == transcribing }
        )
        for record in Self.keepOrder((try? context.fetch(descriptor)) ?? []) {
            enqueueTranscription(Attempt(id: record.id, isVisible: true))
        }
    }

    /// What a launch tries again: the model may be installed by now, a language change may have
    /// made the device supported, and an analysis error gets its one retry.
    private func retryTranscriptionsAtLaunch() {
        retryTranscriptionsWaitingForModel()
        retryTranscriptionsAfterLocaleChange()
        for record in noTranscriptRecords(retry: .atNextLaunch) {
            // Cleared before it runs, so a quit mid-retry or a second error never schedules more.
            record.transcriptRetry = .never
            save()
            enqueueTranscription(Attempt(id: record.id, isVisible: false, isErrorRetry: true))
        }
    }

    private func noTranscriptRecords(retry: TranscriptRetry) -> [MemoRecord] {
        let voice = Memo.Kind.voice.rawValue
        let none = Memo.TranscriptState.noTranscript.rawValue
        let raw = retry.rawValue
        let descriptor = FetchDescriptor<MemoRecord>(
            predicate: #Predicate { $0.kindRaw == voice && $0.transcriptStateRaw == none && $0.transcriptRetryRaw == raw }
        )
        return Self.keepOrder((try? context.fetch(descriptor)) ?? [])
    }

    /// **Try again**: Transcribing shows at once.
    private func beginTranscribing(_ record: MemoRecord) {
        record.transcriptState = .transcribing
        record.transcriptRetry = .never
        save()
        refreshForCurrentDay()
        enqueueTranscription(Attempt(id: record.id, isVisible: true))
    }

    private func watchTranscriberReadiness() {
        let readiness = transcriber.readinessUpdates()
        readinessTask = Task { [weak self] in
            for await _ in readiness {
                guard let self else { return }
                self.retryTranscriptionsWaitingForModel()
            }
        }
    }

    private func watchDeviceLocale() {
        localeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSLocale.currentLocaleDidChangeNotification) {
                guard let self else { return }
                self.retryTranscriptionsAfterLocaleChange()
            }
        }
    }

    private func enqueueTranscription(_ attempt: Attempt) {
        if let index = pendingTranscriptions.firstIndex(where: { $0.id == attempt.id }) {
            // Already waiting: a visible request makes the wait visible.
            pendingTranscriptions[index].isVisible = pendingTranscriptions[index].isVisible || attempt.isVisible
            return
        }
        // A background retry of what's already running adds nothing.
        if !attempt.isVisible, runningTranscriptionID == attempt.id { return }
        pendingTranscriptions.append(attempt)
        guard transcriptionTask == nil else { return }
        transcriptionTask = Task { [weak self] in
            await self?.drainTranscriptions()
        }
    }

    /// One memo at a time, since the system limits simultaneous analyses.
    private func drainTranscriptions() async {
        while !pendingTranscriptions.isEmpty {
            let attempt = pendingTranscriptions.removeFirst()
            guard let audio = audioData(forMemoID: attempt.id) else { continue }
            runningTranscriptionID = attempt.id
            let outcome = await transcriber.transcribe(audio: audio, memoID: attempt.id)
            runningTranscriptionID = nil
            apply(outcome, to: attempt)
        }
        transcriptionTask = nil
    }

    private func apply(_ outcome: TranscriptionOutcome, to attempt: Attempt) {
        // Deleted while transcribing, or already settled some other way (a background retry
        // overtaken by **Try again**): nothing to do.
        let expected: Memo.TranscriptState = attempt.isVisible ? .transcribing : .noTranscript
        guard let record = records(withID: attempt.id).first, record.transcriptState == expected else { return }

        var transcript: String?
        if case .transcript(let text) = outcome {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            transcript = trimmed.isEmpty ? nil : trimmed
        }
        if let transcript {
            record.text = transcript
            record.transcriptState = .transcribed
            record.transcriptRetry = .never
        } else {
            record.transcriptState = .noTranscript
            switch outcome {
            case .modelNotReady:
                record.transcriptRetry = .whenModelReady
            case .unsupported:
                record.transcriptRetry = .onLocaleChange
                record.transcriptLocaleIdentifier = deviceLocale()
            case .failed:
                record.transcriptRetry = attempt.isErrorRetry ? .never : .atNextLaunch
            case .transcript, .noSpeech:
                record.transcriptRetry = .never
            }
        }
        save()
        // A background retry that fails changes nothing the user can see.
        if attempt.isVisible || transcript != nil {
            refreshForCurrentDay()
        }
        if let transcript {
            enqueueTitle(for: record, transcript: transcript)
        }
    }

    // MARK: Titles

    /// A Transcript has just been finalized for the first time: its title is generated now or
    /// never. A title the user already set stays, and without Apple Intelligence the "Voice
    /// memo" fallback stays, with no retry later.
    private func enqueueTitle(for record: MemoRecord, transcript: String) {
        guard !record.titleIsUserSet, languageModel.availability.isAvailable else { return }
        pendingTitles.append(TitleRequest(id: record.id, transcript: transcript))
        guard titleTask == nil else { return }
        titleTask = Task { [weak self] in
            await self?.drainTitles()
        }
    }

    /// One at a time, so the on-device model never serves several memos at once.
    private func drainTitles() async {
        while !pendingTitles.isEmpty {
            let request = pendingTitles.removeFirst()
            // From the start of the Transcript, as much as fits.
            let text = await languageModel.fittingStart(of: request.transcript, for: .title)
            guard !text.isEmpty, let proposed = try? await languageModel.generateTitle(from: text) else { continue }
            applyGeneratedTitle(proposed, toMemoWithID: request.id)
        }
        titleTask = nil
    }

    private func applyGeneratedTitle(_ proposed: String, toMemoWithID id: UUID) {
        let title = Self.generatedTitle(from: proposed)
        // Deleted, or renamed by the user while it was generating: the user's title wins.
        guard !title.isEmpty, let record = records(withID: id).first, !record.titleIsUserSet else { return }
        record.title = title
        save()
        refreshForCurrentDay()
    }

    /// Whitespace and line breaks collapsed to single spaces, so a title is one line.
    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let maximumGeneratedTitleLength = 80

    /// What the model proposed, as one line without the quotes or final period models like to
    /// add, and no longer than a row can sensibly show.
    private static func generatedTitle(from proposed: String) -> String {
        var title = singleLine(proposed)
        let decoration = CharacterSet(charactersIn: "\"'“”‘’.")
        title = title.trimmingCharacters(in: decoration).trimmingCharacters(in: .whitespaces)
        if title.count > maximumGeneratedTitleLength {
            title = String(title.prefix(maximumGeneratedTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        return title
    }

    private func save() {
        if context.hasChanges {
            try? context.save()
        }
    }

    /// One record per id. Extras are deleted (duplicates are removed by id in app code); the one
    /// kept never depends on fetch order.
    private func uniqueByID(_ records: [MemoRecord]) -> [MemoRecord] {
        var seen = Set<UUID>()
        var unique: [MemoRecord] = []
        for record in Self.keepOrder(records) {
            if seen.insert(record.id).inserted {
                unique.append(record)
            } else {
                deleteIncludingMedia(record)
            }
        }
        save()
        return unique
    }

    private static func keepOrder(_ records: [MemoRecord]) -> [MemoRecord] {
        records.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.text < rhs.text
        }
    }

    /// Later days first, then newer within a day.
    private static func isNewerDayFirst(_ lhs: Memo, _ rhs: Memo) -> Bool {
        let (left, right) = (lhs.day, rhs.day)
        if left != right {
            return (left.era ?? 0, left.year, left.month, left.day) > (right.era ?? 0, right.year, right.month, right.day)
        }
        return isNewer(lhs, rhs)
    }

    /// A day as one number that orders like the calendar: 20261006.
    private static func dayKey(_ day: TaskCompletionDay) -> Int {
        day.year * 10_000 + day.month * 100 + day.day
    }

    private static func isNewer(_ lhs: Memo, _ rhs: Memo) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
