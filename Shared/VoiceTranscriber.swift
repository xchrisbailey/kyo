import Foundation

/// How a transcription ended.
enum TranscriptionOutcome: Equatable, Sendable {
    case transcript(String)
    /// The audio was analyzed and nothing was recognized (silence). The memo is **No transcript**
    /// and doesn't retry by itself; **Try again** still works.
    case noSpeech
    /// Transcription couldn't run: the speech model isn't installed yet, the device or language
    /// isn't supported, or the analysis failed. The memo is **No transcript** and retries by
    /// itself once the transcriber reports readiness (see `readinessUpdates()`), and when Kyo
    /// next launches or comes to the front.
    case unavailable
}

/// The transcriber seam: turns a **Voice memo**'s audio into its **Transcript**. The store runs
/// one transcription at a time. The real one is `SpeechVoiceTranscriber`, which keeps every
/// Speech-framework call out of the rest of the app.
protocol VoiceTranscriber: Sendable {
    /// `audio` is the memo's stored audio.
    func transcribe(audio: Data, memoID: UUID) async -> TranscriptionOutcome

    /// Yields each time something that kept transcription from working may have cleared, for
    /// example the speech model finishing its install or the network coming back. The store
    /// then retries the memos that ended `.unavailable`. Read once, by the store.
    func readinessUpdates() -> AsyncStream<Void>
}

extension VoiceTranscriber {
    /// A transcriber with nothing to wait for never reports readiness.
    func readinessUpdates() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

/// Transcribes nothing: every Voice memo ends as **No transcript**, with its audio kept.
struct NoTranscriber: VoiceTranscriber {
    func transcribe(audio: Data, memoID: UUID) async -> TranscriptionOutcome {
        .unavailable
    }
}
