import Foundation
import XCTest

/// A stand-in for the microphone: no hardware, scripted access, and recorded audio that is just
/// bytes. Tests drive time through the session's clock, and interruptions through
/// `simulateInterruption()`.
@MainActor
final class FakeAudioRecorder: AudioRecording {
    struct StartFailure: Error {}
    struct StillInterrupted: Error {}
    struct StopFailure: Error {}

    var microphoneAccess: MicrophoneAccess
    /// What the system prompt answers when `microphoneAccess` is `.undetermined`.
    var promptAnswer: MicrophoneAccess = .granted
    private(set) var promptCount = 0

    var interruptionHandler: (@MainActor () -> Void)?
    var level: Float = 0.5

    /// What `stop()` returns.
    var recordedBytes = Data([0xA1, 0xA2, 0xA3])
    var startError: Error?
    /// While `true`, `resume()` throws, as when a call is still going.
    var isAudioTaken = false
    var stopError: Error?
    /// What `recoverPartialRecordings()` returns.
    var partialRecordings: [RecordedAudio] = []

    private(set) var isCapturing = false
    private(set) var startedIDs: [UUID] = []
    private(set) var discardCount = 0
    private(set) var removedFileIDs: [UUID] = []

    init(access: MicrophoneAccess = .granted) {
        microphoneAccess = access
    }

    func requestMicrophoneAccess() async -> MicrophoneAccess {
        promptCount += 1
        microphoneAccess = promptAnswer
        return promptAnswer
    }

    func start(recordingID: UUID, startedAt: Date) async throws {
        if let startError { throw startError }
        startedIDs.append(recordingID)
        isCapturing = true
    }

    func pause() {
        isCapturing = false
    }

    func resume() async throws {
        if isAudioTaken { throw StillInterrupted() }
        isCapturing = true
    }

    func stop() throws -> Data {
        isCapturing = false
        if let stopError { throw stopError }
        return recordedBytes
    }

    func discard() {
        isCapturing = false
        discardCount += 1
    }

    func recoverPartialRecordings() -> [RecordedAudio] {
        partialRecordings
    }

    func removeRecordingFile(id: UUID) {
        removedFileIDs.append(id)
        partialRecordings.removeAll { $0.id == id }
    }

    /// Something else takes the audio, as a call or Siri would.
    func simulateInterruption() {
        isCapturing = false
        interruptionHandler?()
    }
}

/// A transcriber that returns a scripted outcome, either at once or when the test releases it.
final class ScriptedTranscriber: VoiceTranscriber, @unchecked Sendable {
    private let lock = NSLock()
    private var immediate: TranscriptionOutcome?
    private var received: [UUID] = []
    private var running = 0
    private var peak = 0
    private let held: AsyncStream<TranscriptionOutcome>
    private let heldContinuation: AsyncStream<TranscriptionOutcome>.Continuation
    private let readiness: AsyncStream<Void>
    private let readinessContinuation: AsyncStream<Void>.Continuation

    /// `immediate` answers every call at once; `nil` holds each call until `release(_:)`.
    init(immediate: TranscriptionOutcome? = nil) {
        self.immediate = immediate
        (held, heldContinuation) = AsyncStream<TranscriptionOutcome>.makeStream()
        (readiness, readinessContinuation) = AsyncStream<Void>.makeStream()
    }

    /// Changes what calls answer at once from now on; `nil` holds them until `release(_:)`.
    func answer(with outcome: TranscriptionOutcome?) {
        lock.withLock { immediate = outcome }
    }

    /// What the cause clearing looks like: the model finishing its install, the network coming
    /// back.
    func becomeReady() {
        readinessContinuation.yield()
    }

    func readinessUpdates() -> AsyncStream<Void> {
        readiness
    }

    /// The ids transcribed so far, in order.
    var transcribedIDs: [UUID] {
        lock.withLock { received }
    }

    /// The most calls that ever ran at the same time.
    var peakConcurrency: Int {
        lock.withLock { peak }
    }

    func release(_ outcome: TranscriptionOutcome) {
        heldContinuation.yield(outcome)
    }

    func transcribe(audio: Data, memoID: UUID) async -> TranscriptionOutcome {
        let answer: TranscriptionOutcome? = lock.withLock {
            received.append(memoID)
            running += 1
            peak = max(peak, running)
            return immediate
        }
        defer { lock.withLock { running -= 1 } }
        if let answer { return answer }
        for await outcome in held {
            return outcome
        }
        return .failed
    }
}

/// A stand-in for live transcription from the microphone: scripted availability, and words the
/// test "hears" when it chooses.
@MainActor
final class FakeLiveTranscriber: LiveTranscribing {
    /// What `start` answers.
    var isAvailable = true
    /// While `true`, `start` waits for `finishPendingStart()`.
    var holdsStart = false

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onUpdate: (@MainActor (String) -> Void)?
    private var pendingStart: CheckedContinuation<Void, Never>?

    func start(onUpdate: @escaping @MainActor (String) -> Void) async -> Bool {
        startCount += 1
        let stopsBefore = stopCount
        if holdsStart {
            await withCheckedContinuation { pendingStart = $0 }
        }
        // A stop while starting means nothing was started, as in the real one.
        guard isAvailable, stopCount == stopsBefore else { return false }
        self.onUpdate = onUpdate
        return true
    }

    func stop() {
        stopCount += 1
        onUpdate = nil
    }

    /// Words reach the recorder only while listening.
    func hear(_ text: String) {
        onUpdate?(text)
    }

    func finishPendingStart() {
        pendingStart?.resume()
        pendingStart = nil
    }
}
