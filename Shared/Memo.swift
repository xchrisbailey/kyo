import Foundation

/// A **Memo** as the rest of the app sees it: a captured thought that belongs to the local
/// calendar day it was created. A **Written memo** is its text; a **Voice memo** keeps its audio
/// and has a **Transcript**, which is its only text.
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

    /// The title a Voice memo has until an AI or user title exists.
    static let voiceFallbackTitle = "Voice memo"

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

    init(
        id: UUID,
        kind: Kind,
        createdAt: Date,
        day: TaskCompletionDay,
        text: String,
        duration: TimeInterval = 0,
        transcriptState: TranscriptState? = nil,
        stoppedAtCap: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.day = day
        self.text = text
        self.duration = duration
        self.transcriptState = transcriptState
        self.stoppedAtCap = stoppedAtCap
    }

    /// A Written memo's first non-blank line, trimmed (empty when it has no text). A Voice memo
    /// is "Voice memo".
    var title: String {
        switch kind {
        case .written: Self.title(ofWrittenText: text)
        case .voice: Self.voiceFallbackTitle
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

    /// The note a capped Voice memo shows, or `nil`.
    var capNote: String? {
        stoppedAtCap ? "Recording stopped at 10 minutes" : nil
    }

    static func title(ofWrittenText text: String) -> String {
        lines(of: text).first ?? ""
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
