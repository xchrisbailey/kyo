import Combine
import Foundation
import SwiftData

/// What the views consume to capture and show **Memos**. Today's memos are listed newest
/// first. A memo belongs to the local calendar day it was created and never moves.
@MainActor
protocol MemoStoreBehavior: AnyObject {
    /// Only the memos whose day is Today, newest first.
    var memos: [Memo] { get }
    /// "2 memos" (or "1 memo") when Today has memos, "Notes & voice" when it has none.
    var sectionSubtitle: String { get }

    /// Any memo, from any day, by id.
    func memo(id: UUID) -> Memo?
    /// Saves a Written memo on Today. A memo with no text is discarded: returns `nil`.
    @discardableResult func addWrittenMemo(text: String) -> Memo?
    /// Saves a Voice memo as soon as recording stops, on the day recording started, in
    /// Transcribing, and starts transcribing it. Saving the same recording again returns the
    /// memo already saved.
    @discardableResult func addVoiceMemo(_ audio: RecordedAudio, stoppedAtCap: Bool) -> Memo
    /// Saves new text immediately (a Voice memo's text is its Transcript). Emptying a Written
    /// memo's text keeps the memo until it's closed.
    @discardableResult func editMemo(id: UUID, text: String) -> Memo?
    /// Called when a memo's card closes. Discards a Written memo with no text, returning it. A
    /// Voice memo is never discarded this way.
    @discardableResult func closeMemo(id: UUID) -> Memo?
    /// Permanent: no undo and no trash. Removes a Voice memo's audio too.
    @discardableResult func deleteMemo(id: UUID) -> Memo?

    /// A Voice memo's stored audio, or `nil` for a Written memo or an unknown id.
    func audioData(forMemoID id: UUID) -> Data?
    /// **Try again** on a Voice memo with No transcript: transcribes it again.
    @discardableResult func retryTranscription(id: UUID) -> Memo?
}

@MainActor
final class MemoStore: ObservableObject, MemoStoreBehavior {
    @Published private(set) var memos: [Memo] = []
    @Published private(set) var currentDate: Date

    /// Held so the container, and with it the context, outlives every use of the store.
    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let now: () -> Date
    private let calendar: Calendar
    private let transcriber: any VoiceTranscriber

    private var pendingTranscriptions: [UUID] = []
    private var transcriptionTask: Task<Void, Never>?

    /// `now` and `calendar` make the current day controllable. A memo's day is taken from them
    /// when it's created and then kept. The `transcriber` fills in Voice memo Transcripts, one
    /// at a time.
    init(
        modelContainer: ModelContainer,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        transcriber: any VoiceTranscriber = NoTranscriber()
    ) {
        self.modelContainer = modelContainer
        self.context = modelContainer.mainContext
        self.now = now
        self.calendar = calendar
        self.transcriber = transcriber
        self.currentDate = calendar.startOfDay(for: now())
        discardEmptyWrittenMemos()
        refreshForCurrentDay()
        resumeInterruptedTranscriptions()
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

    @discardableResult
    func addWrittenMemo(text: String) -> Memo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let createdAt = now()
        let record = MemoRecord(
            kind: .written,
            createdAt: createdAt,
            day: TaskCompletionDay(date: createdAt, calendar: calendar),
            text: trimmed
        )
        context.insert(record)
        save()
        refreshForCurrentDay()
        return record.memo
    }

    @discardableResult
    func addVoiceMemo(_ audio: RecordedAudio, stoppedAtCap: Bool) -> Memo {
        // The recording's id is the memo's id, so saving a recording twice keeps one memo.
        if let existing = records(withID: audio.id).first {
            return existing.memo
        }
        let record = MemoRecord(
            id: audio.id,
            kind: .voice,
            createdAt: audio.startedAt,
            day: TaskCompletionDay(date: audio.startedAt, calendar: calendar),
            text: "",
            durationSeconds: audio.duration,
            transcriptState: .transcribing,
            stoppedAtCap: stoppedAtCap
        )
        record.audio = MemoAudioRecord(data: audio.data)
        context.insert(record)
        save()
        refreshForCurrentDay()
        enqueueTranscription(of: audio.id)
        return record.memo
    }

    func audioData(forMemoID id: UUID) -> Data? {
        records(withID: id).first?.audio?.data
    }

    @discardableResult
    func retryTranscription(id: UUID) -> Memo? {
        guard let record = records(withID: id).first, record.kind == .voice else { return nil }
        if record.transcriptState == .noTranscript {
            record.transcriptState = .transcribing
            save()
            refreshForCurrentDay()
            enqueueTranscription(of: id)
        }
        return record.memo
    }

    /// Returns once every transcription started so far has finished. For tests.
    func transcriptionsSettled() async {
        while let task = transcriptionTask {
            await task.value
        }
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
        guard let record = records(withID: id).first, record.kind == .written, record.text.isEmpty else { return nil }
        return deleteMemo(id: id)
    }

    @discardableResult
    func deleteMemo(id: UUID) -> Memo? {
        let matches = records(withID: id)
        guard let first = matches.first else { return nil }
        let removed = first.memo
        for record in matches {
            deleteIncludingAudio(record)
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

    /// A Written memo emptied while its card was open, then left behind by a quit, is discarded
    /// on the next launch: a Written memo with no text is never kept. Only Written memos are
    /// judged by their text; a Voice memo (and, later, a photo memo) legitimately has none.
    private func discardEmptyWrittenMemos() {
        let written = Memo.Kind.written.rawValue
        let descriptor = FetchDescriptor<MemoRecord>(predicate: #Predicate { $0.kindRaw == written && $0.text == "" })
        for record in (try? context.fetch(descriptor)) ?? [] {
            deleteIncludingAudio(record)
        }
        save()
    }

    private func deleteIncludingAudio(_ record: MemoRecord) {
        if let audio = record.audio {
            context.delete(audio)
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
            enqueueTranscription(of: record.id)
        }
    }

    private func enqueueTranscription(of id: UUID) {
        guard !pendingTranscriptions.contains(id) else { return }
        pendingTranscriptions.append(id)
        guard transcriptionTask == nil else { return }
        transcriptionTask = Task { [weak self] in
            await self?.drainTranscriptions()
        }
    }

    /// One memo at a time, since the system limits simultaneous analyses.
    private func drainTranscriptions() async {
        while !pendingTranscriptions.isEmpty {
            let id = pendingTranscriptions.removeFirst()
            guard let audio = audioData(forMemoID: id) else { continue }
            let outcome = await transcriber.transcribe(audio: audio, memoID: id)
            apply(outcome, toMemoWithID: id)
        }
        transcriptionTask = nil
    }

    private func apply(_ outcome: TranscriptionOutcome, toMemoWithID id: UUID) {
        // Deleted while transcribing, or already settled some other way: nothing to do.
        guard let record = records(withID: id).first, record.transcriptState == .transcribing else { return }
        switch outcome {
        case .transcript(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                record.transcriptState = .noTranscript
            } else {
                record.text = trimmed
                record.transcriptState = .transcribed
            }
        case .noTranscript:
            record.transcriptState = .noTranscript
        }
        save()
        refreshForCurrentDay()
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
                deleteIncludingAudio(record)
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

    private static func isNewer(_ lhs: Memo, _ rhs: Memo) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
