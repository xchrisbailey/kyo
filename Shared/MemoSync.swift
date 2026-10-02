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
    /// A Written memo with no text and at least one photo, which a row shows with the photo icon.
    let isPhotoOnly: Bool

    init(
        id: UUID, day: TaskCompletionDay, createdAt: Date, kind: Memo.Kind, title: String,
        voiceState: Memo.TranscriptState? = nil, duration: TimeInterval = 0, photoCount: Int = 0,
        isPhotoOnly: Bool = false
    ) {
        self.id = id
        self.day = day
        self.createdAt = createdAt
        self.kind = kind
        self.title = title
        self.voiceState = voiceState
        self.duration = duration
        self.photoCount = photoCount
        self.isPhotoOnly = isPhotoOnly
    }

    private enum CodingKeys: String, CodingKey {
        case id, day, createdAt, kind, title, voiceState, duration, photoCount, isPhotoOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        day = try container.decode(TaskCompletionDay.self, forKey: .day)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decode(Memo.Kind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        voiceState = try container.decodeIfPresent(Memo.TranscriptState.self, forKey: .voiceState)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        photoCount = try container.decode(Int.self, forKey: .photoCount)
        // Snapshots published before the Watch showed the photo icon never carried this field.
        isPhotoOnly = try container.decodeIfPresent(Bool.self, forKey: .isPhotoOnly) ?? false
    }

    init(_ memo: Memo) {
        self.init(
            id: memo.id, day: memo.day, createdAt: memo.createdAt, kind: memo.kind, title: memo.title,
            voiceState: memo.transcriptState, duration: memo.duration, photoCount: memo.photoCount,
            isPhotoOnly: memo.isPhotoOnly
        )
    }

    /// The parts of the row's second line, which always starts with the time (a Watch row has no
    /// time column, so it's what tells Transcribing and No transcript rows apart): a Voice
    /// memo's duration and, unless it is transcribed, its state (Transcribing shows no duration),
    /// then the photo count when there are photos.
    private func detailParts(locale: Locale, timeZone: TimeZone) -> [String] {
        var parts = [timeText(locale: locale, timeZone: timeZone)]
        if kind == .voice {
            switch voiceState ?? .noTranscript {
            case .transcribing: parts.append("Transcribing…")
            case .noTranscript: parts += [Memo.formattedDuration(duration), "No transcript"]
            case .transcribed: parts.append(Memo.formattedDuration(duration))
            }
        }
        if let photos = photoText { parts.append(photos) }
        return parts
    }

    /// The row's second line: "9:41 AM · 0:42 · 2 photos" (transcribed), "9:41 AM · Transcribing…",
    /// "9:41 AM · 0:42 · No transcript", or for a Written memo "9:41 AM · 2 photos" or "9:41 AM".
    func detailLine(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        detailParts(locale: locale, timeZone: timeZone).joined(separator: " · ")
    }

    /// What VoiceOver says: the kind, the title, then the same parts as the detail line.
    func accessibilityLabel(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let kindName = isPhotoOnly ? Memo.photoOnlyTitle : (kind == .voice ? "Voice memo" : "Written memo")
        return ([kindName, title] + detailParts(locale: locale, timeZone: timeZone)).joined(separator: ", ")
    }

    private func timeText(locale: Locale, timeZone: TimeZone) -> String {
        Self.timeText(of: createdAt, locale: locale, timeZone: timeZone)
    }

    static func timeText(of date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
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
    /// Ids of Watch recordings the phone has received and saved. The Watch outbox retires
    /// entries on these, mirroring `acknowledgedCommandIDs`.
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
