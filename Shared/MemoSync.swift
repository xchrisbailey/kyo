import Foundation

/// One of today's memos as the Watch sees it: just what a Watch row shows. No text, transcript,
/// audio or photos ever travel to the Watch. See `docs/adr/0005-watch-memo-sync.md`.
struct WatchMemo: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    /// The memo's own day, so the Watch can keep showing only memos whose day is its own Today.
    let day: TaskCompletionDay
    let createdAt: Date
    let kind: Memo.Kind
    /// The title as a row shows it, with the "Voice memo" and "Photo memo" fallbacks applied.
    let title: String
    /// A Voice memo's Transcript state. `nil` for a Written memo.
    let voiceState: Memo.TranscriptState?
    /// A Voice memo's recorded length in seconds. Zero for a Written memo.
    let duration: TimeInterval
    let photoCount: Int

    init(
        id: UUID, day: TaskCompletionDay, createdAt: Date, kind: Memo.Kind, title: String,
        voiceState: Memo.TranscriptState? = nil, duration: TimeInterval = 0, photoCount: Int = 0
    ) {
        self.id = id
        self.day = day
        self.createdAt = createdAt
        self.kind = kind
        self.title = title
        self.voiceState = voiceState
        self.duration = duration
        self.photoCount = photoCount
    }

    init(_ memo: Memo) {
        self.init(
            id: memo.id, day: memo.day, createdAt: memo.createdAt, kind: memo.kind, title: memo.title,
            voiceState: memo.transcriptState, duration: memo.duration, photoCount: memo.photoCount
        )
    }

    /// A Voice memo that is Transcribing or has No transcript shows that instead of its details.
    private var transcriptStatus: String? {
        guard kind == .voice else { return nil }
        switch voiceState ?? .noTranscript {
        case .transcribing: return "Transcribing…"
        case .noTranscript: return "No transcript"
        case .transcribed: return nil
        }
    }

    /// The row's second line: "9:41 AM · 0:42 · 2 photos" (a Written memo has no duration, and
    /// a memo with no photos no photo count), or "Transcribing…" / "No transcript".
    func detailLine(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        if let transcriptStatus { return transcriptStatus }
        var parts = [timeText(locale: locale, timeZone: timeZone)]
        if kind == .voice { parts.append(Memo.formattedDuration(duration)) }
        if let photos = photoText { parts.append(photos) }
        return parts.joined(separator: " · ")
    }

    /// What VoiceOver says: the kind, the title, the time, then the duration or transcript state
    /// and the photo count.
    func accessibilityLabel(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var parts = [kind == .voice ? "Voice memo" : "Written memo", title]
        parts.append(timeText(locale: locale, timeZone: timeZone))
        if kind == .voice { parts.append(Memo.formattedDuration(duration)) }
        if let transcriptStatus { parts.append(transcriptStatus) }
        if let photos = photoText { parts.append(photos) }
        return parts.joined(separator: ", ")
    }

    private func timeText(locale: Locale, timeZone: TimeZone) -> String {
        createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    private var photoText: String? {
        photoCount > 0 ? (photoCount == 1 ? "1 photo" : "\(photoCount) photos") : nil
    }
}

/// The phone's memos for its Today, published to the Watch under their own context key and
/// revision, so publishing memos never disturbs the task or habit snapshots. See
/// `docs/adr/0005-watch-memo-sync.md`.
///
/// The revision follows ADR 0001's hybrid clock and reconciliation rule. `memos` is newest
/// first. The Watch filters it to its own Today, so the list empties at midnight without the
/// phone.
struct MemoListSnapshot: Codable, Equatable, Sendable {
    let revision: Int64
    let memos: [WatchMemo]
    /// Ids of Watch recordings the phone has received and saved. The Watch outbox (#86) retires
    /// entries on these, mirroring `acknowledgedCommandIDs`; nothing fills it yet.
    let acknowledgedMemoIDs: [UUID]

    init(revision: Int64, memos: [WatchMemo], acknowledgedMemoIDs: [UUID] = []) {
        self.revision = revision
        self.memos = memos
        self.acknowledgedMemoIDs = acknowledgedMemoIDs
    }

    private enum CodingKeys: String, CodingKey {
        case revision, memos, acknowledgedMemoIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(Int64.self, forKey: .revision)
        memos = try container.decode([WatchMemo].self, forKey: .memos)
        // Snapshots published before Watch recording never carried this field.
        acknowledgedMemoIDs = try container.decodeIfPresent([UUID].self, forKey: .acknowledgedMemoIDs) ?? []
    }
}

/// Carries `MemoListSnapshot`s from the phone to the Watch. Like task and habit snapshots,
/// undelivered earlier snapshots may be dropped in favor of the latest.
@MainActor
protocol MemoSnapshotTransport: AnyObject {
    /// Makes `snapshot` the latest memo list available to the counterpart.
    func publish(_ snapshot: MemoListSnapshot)
    /// Registers the receiver. If a snapshot was already received, deliver the latest one immediately.
    func setMemoSnapshotHandler(_ handler: @escaping @MainActor (MemoListSnapshot) -> Void)
}
