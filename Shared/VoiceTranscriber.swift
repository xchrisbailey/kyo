import Foundation

/// How a transcription ended.
enum TranscriptionOutcome: Equatable, Sendable {
    case transcript(String)
    /// The audio has no transcript: nothing was recognized, or transcription isn't available.
    case noTranscript
}

/// The transcriber seam: turns a **Voice memo**'s audio into its **Transcript**. The store runs
/// one transcription at a time. "Transcribe voice memos on device" plugs the Speech framework in
/// behind this, and may extend the outcome (for example to tell a missing model, which retries
/// by itself, from silence, which doesn't).
protocol VoiceTranscriber: Sendable {
    /// `audio` is the memo's stored AAC audio.
    func transcribe(audio: Data, memoID: UUID) async -> TranscriptionOutcome
}

/// Transcribes nothing: every Voice memo ends as **No transcript**, with its audio kept.
struct NoTranscriber: VoiceTranscriber {
    func transcribe(audio: Data, memoID: UUID) async -> TranscriptionOutcome {
        .noTranscript
    }
}
