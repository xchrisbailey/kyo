import AVFoundation
import Foundation
import Speech

/// The real `VoiceTranscriber`: transcribes a saved **Voice memo** on device with
/// `SpeechAnalyzer`, using `SpeechTranscriber` and falling back to `DictationTranscriber` (see
/// `SpeechSupport.resolve`). It runs on the device's language and checks availability each time:
/// a model that isn't installed is `.modelNotReady`, a device or language neither module serves
/// is `.unsupported`, and an analysis that throws is `.failed`.
///
/// Transcription doesn't run in the Simulator, so this is checked on a device; the behavior
/// around it is tested through the `VoiceTranscriber` seam.
struct SpeechVoiceTranscriber: VoiceTranscriber {
    let support: SpeechSupport

    func transcribe(audio: Data, memoID: UUID) async -> TranscriptionOutcome {
        let choice: SpeechSupport.Choice
        switch await support.resolve(.file) {
        case .ready(let ready): choice = ready
        case .notInstalled: return .modelNotReady
        case .unsupported: return .unsupported
        }

        await support.gate.acquire()
        let outcome: TranscriptionOutcome
        do {
            let text = try await transcribe(audio, as: memoID, with: choice)
            outcome = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .noSpeech : .transcript(text)
        } catch {
            outcome = .failed
        }
        await support.gate.release()
        return outcome
    }

    func readinessUpdates() -> AsyncStream<Void> {
        support.readiness
    }

    // MARK: Analysis

    /// The analyzer reads a file, so the memo's audio goes to a temporary one, removed afterwards.
    private func transcribe(_ audio: Data, as memoID: UUID, with choice: SpeechSupport.Choice) async throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(memoID.uuidString).\(Self.fileExtension(for: audio))", directoryHint: .notDirectory)
        try audio.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = try await AssetInputSequenceProvider.provider(
            from: AVURLAsset(url: url),
            compatibleWith: [choice.module]
        )
        let analyzer = SpeechAnalyzer(
            modules: [choice.module],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        )

        // Results are read while the analysis runs, as the streams only end once it finishes.
        let heard = choice.heard()
        let collector = Task {
            var text = ""
            for try await result in heard where result.isFinal {
                text += result.text
            }
            return text
        }
        do {
            if let lastSample = try await analyzer.analyzeSequence(provider.analyzerInputs) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw error
        }
        return try await collector.value
    }

    /// A recording is a CAF (see `DeviceAudioRecorder`), and so is one from the Watch (see
    /// `WatchAudioRecorder`), but an M4A is still read.
    private static func fileExtension(for audio: Data) -> String {
        audio.starts(with: Array("caff".utf8)) ? "caf" : "m4a"
    }
}
