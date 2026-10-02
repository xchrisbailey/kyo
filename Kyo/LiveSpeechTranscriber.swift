import AVFoundation
import Foundation
import Speech

/// The real `LiveTranscribing`: feeds the microphone to a `SpeechAnalyzer` through
/// `CaptureInputSequenceProvider` and reports the progressive results (words still changing
/// plus the finalized ones). It uses its own capture session next to `DeviceAudioRecorder`, so
/// the audio the memo keeps is untouched. The recorder owns the app's audio session: capture
/// never reconfigures it, starts only after the recorder has activated it, and
/// `waitUntilStopped()` lets the recorder hold its deactivation until capture has let go.
///
/// Live transcription takes the analysis gate for as long as it listens, so it only starts
/// when no memo is being transcribed from its file; otherwise recording goes on without it.
/// Doesn't run in the Simulator; checked on a device.
@MainActor
final class LiveSpeechTranscriber: LiveTranscribing {
    /// The capture session isn't `Sendable`; it's only started and stopped, off the main thread.
    private final class CaptureBox: @unchecked Sendable {
        let session: AVCaptureSession
        init(_ session: AVCaptureSession) { self.session = session }
    }

    private struct Running {
        let capture: CaptureBox
        let analyzer: SpeechAnalyzer
        let results: Task<Void, Never>
    }

    private let support: SpeechSupport
    private var generation = 0
    private var running: Running?
    /// The previous stop, which a new start waits for so the gate is free again.
    private var teardown: Task<Void, Never>?

    init(support: SpeechSupport) {
        self.support = support
    }

    func start(onUpdate: @escaping @MainActor (String) -> Void) async -> Bool {
        generation += 1
        let mine = generation
        await teardown?.value
        guard mine == generation, running == nil else { return false }
        guard let device = AVCaptureDevice.default(for: .audio) else { return false }
        guard await support.gate.tryAcquire() else { return false }
        guard mine == generation else {
            await support.gate.release()
            return false
        }

        do {
            guard case .ready(let choice) = await support.resolve(.live) else { throw LiveError.notAvailable }
            let session = AVCaptureSession()
            // The recorder owns the audio session; capture must not reconfigure it.
            session.automaticallyConfiguresApplicationAudioSession = false
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw LiveError.notAvailable }
            session.addInput(input)
            let provider = try await CaptureInputSequenceProvider.provider(
                from: device,
                in: session,
                compatibleWith: [choice.module]
            )
            guard session.canAddOutput(provider.captureAudioDataOutput) else { throw LiveError.notAvailable }
            session.addOutput(provider.captureAudioDataOutput)

            // Nothing below suspends, so a `stop()` can't slip in before `running` is set.
            guard mine == generation else { throw LiveError.stopped }
            let analyzer = SpeechAnalyzer(inputSequence: provider.analyzerInputs, modules: [choice.module])
            let heard = choice.heard()
            let results = Task { [weak self] in
                var finalized = ""
                var volatile = ""
                do {
                    for try await result in heard {
                        if result.isFinal {
                            finalized += result.text
                            volatile = ""
                        } else {
                            volatile = result.text
                        }
                        let text = finalized + volatile
                        await MainActor.run {
                            guard let self, self.generation == mine else { return }
                            onUpdate(text)
                        }
                    }
                } catch {
                    // The analysis ended early; what was heard stays on screen.
                }
            }
            let capture = CaptureBox(session)
            DispatchQueue.global(qos: .userInitiated).async { capture.session.startRunning() }
            running = Running(capture: capture, analyzer: analyzer, results: results)
            return true
        } catch {
            await support.gate.release()
            return false
        }
    }

    func stop() {
        generation += 1
        guard let running else { return }
        self.running = nil
        let previous = teardown
        let support = support
        teardown = Task {
            await previous?.value
            // Off the main thread, as `stopRunning()` can block.
            let capture = running.capture
            await Task.detached { capture.session.stopRunning() }.value
            running.results.cancel()
            await running.analyzer.cancelAndFinishNow()
            await support.gate.release()
        }
    }

    func waitUntilStopped() async {
        await teardown?.value
    }

    private enum LiveError: Error {
        case notAvailable
        case stopped
    }
}
