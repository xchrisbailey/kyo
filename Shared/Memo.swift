import Foundation

/// A **Memo** as the rest of the app sees it: a captured thought that belongs to the local
/// calendar day it was created. A **Written memo** is its text; a **Voice memo** keeps its audio
/// and has a **Transcript**, which is its only text. Either can carry up to 4 photos, and a
/// Written memo with photos and no text is a photo-only memo.
struct Memo: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case written
        case voice
    }

    /// Where a Voice memo's **Transcript** stands. A new Voice memo is saved as soon as recording
    /// stops, in `transcribing`, and ends as `transcribed` or `noTranscript`.
    enum TranscriptState: String, Sendable {
        case transcribing
        case transcribed
        case noTranscript
    }

    /// The title a Voice memo has until a generated or user title exists.
    static let voiceFallbackTitle = "Voice memo"
    /// The title a photo-only memo has: a Written memo with no text but at least one photo.
    static let photoOnlyTitle = "Photo memo"
    /// The most photos a memo can carry.
    static let maximumPhotos = 4

    let id: UUID
    let kind: Kind
    let createdAt: Date
    /// The local calendar day the memo was created on (for a Voice memo, the day recording
    /// started). Never moves on edit or time-zone change.
    let day: TaskCompletionDay
    /// A Written memo's whole text: the first line is the title and the rest is the detail. For
    /// a Voice memo, its Transcript (empty until transcribed).
    let text: String
    /// A Voice memo's recorded length in seconds. Zero for a Written memo.
    let duration: TimeInterval
    /// A Voice memo's Transcript state. `nil` for a Written memo.
    let transcriptState: TranscriptState?
    /// `true` when recording stopped because it reached the 10-minute cap.
    let stoppedAtCap: Bool
    /// A Voice memo's own title: generated on device, or set by the user. Empty when it has
    /// neither, and always empty for a Written memo, whose title is its first line.
    let voiceTitle: String
    /// `true` once the user has named a Voice memo; a generated title never replaces it.
    let isTitleUserSet: Bool
    /// The ids of the memo's photos, in the order they were added. Never the photo bytes.
    let photoIDs: [UUID]

    init(
        id: UUID,
        kind: Kind,
        createdAt: Date,
        day: TaskCompletionDay,
        text: String,
        duration: TimeInterval = 0,
        transcriptState: TranscriptState? = nil,
        stoppedAtCap: Bool = false,
        voiceTitle: String = "",
        isTitleUserSet: Bool = false,
        photoIDs: [UUID] = []
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.day = day
        self.text = text
        self.duration = duration
        self.transcriptState = transcriptState
        self.stoppedAtCap = stoppedAtCap
        self.voiceTitle = voiceTitle
        self.isTitleUserSet = isTitleUserSet
        self.photoIDs = photoIDs
    }

    var photoCount: Int { photoIDs.count }

    /// A Written memo with photos and no text.
    var isPhotoOnly: Bool {
        kind == .written && Self.title(ofWrittenText: text).isEmpty && !photoIDs.isEmpty
    }

    /// A Written memo's first non-blank line, trimmed, or "Photo memo" when it has no text but has
    /// photos (empty when it has neither). A Voice memo's generated or user title, or "Voice
    /// memo" when it has neither.
    var title: String {
        switch kind {
        case .written: Self.title(ofWrittenText: text, photoCount: photoCount)
        case .voice: voiceTitle.isEmpty ? Self.voiceFallbackTitle : voiceTitle
        }
    }

    /// A Written memo: the text after the title line. A Voice memo: "Transcribing…",
    /// "No transcript", or the Transcript with line breaks collapsed to spaces. `nil` when
    /// there is nothing more to show.
    var detail: String? {
        switch kind {
        case .written:
            Self.detail(ofWrittenText: text)
        case .voice:
            switch transcriptState ?? .noTranscript {
            case .transcribing: "Transcribing…"
            case .noTranscript: "No transcript"
            case .transcribed: Self.collapsed(text)
            }
        }
    }

    /// The text **Memo → Task** reads, given the text as it stands in the open card: a Written
    /// memo's text, or a Voice memo's Transcript once it has one. A Voice memo that is
    /// Transcribing or has No transcript has none, and neither does a photo-only memo.
    func taskSourceText(currentText: String) -> String {
        switch kind {
        case .written: currentText
        case .voice: transcriptState == .transcribed ? currentText : ""
        }
    }

    /// The note a capped Voice memo shows, or `nil`.
    var capNote: String? {
        stoppedAtCap ? "Recording stopped at 10 minutes" : nil
    }

    static func title(ofWrittenText text: String) -> String {
        lines(of: text).first ?? ""
    }

    /// `title(ofWrittenText:)`, or "Photo memo" for a Written memo with no text and photos.
    static func title(ofWrittenText text: String, photoCount: Int) -> String {
        let title = title(ofWrittenText: text)
        return title.isEmpty && photoCount > 0 ? photoOnlyTitle : title
    }

    static func detail(ofWrittenText text: String) -> String? {
        let rest = lines(of: text).dropFirst().joined(separator: " ")
        return rest.isEmpty ? nil : rest
    }

    /// "m:ss" for a length in seconds, rounded down: "0:42", "10:00".
    static func formattedDuration(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    private static func collapsed(_ text: String) -> String? {
        let joined = lines(of: text).joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
