import Foundation

/// Whether Kyo may use the microphone.
enum MicrophoneAccess: Equatable, Sendable {
    /// The system hasn't asked yet.
    case undetermined
    case granted
    case denied
}

/// Why a recording couldn't start or be saved, when the recorder knows.
enum AudioRecordingError: Error, Equatable, Sendable {
    /// The device has no room for the recording. Nothing is saved.
    case outOfSpace
}

/// A finished (or recovered) **Voice memo** recording: AAC, mono, 48 kbps.
struct RecordedAudio: Equatable, Sendable {
    /// Becomes the memo's id, so a recording is never saved twice.
    let id: UUID
    /// When recording started; the memo belongs to this day.
    let startedAt: Date
    /// Seconds of audio, not counting any pause.
    let duration: TimeInterval
    let data: Data
}

/// The recorder seam: everything a **Voice memo** recording needs from the device's microphone and
/// audio session, so behavior tests run with a fake instead of hardware. The real one is
/// `DeviceAudioRecorder`. The elapsed time, the cap and the pause state live in
/// `VoiceRecordingSession`, not here.
///
/// Audio is written to disk as it's captured, so what was recorded up to a crash or quit
/// survives and comes back through `recoverPartialRecordings()`.
@MainActor
protocol AudioRecording: AnyObject {
    var microphoneAccess: MicrophoneAccess { get }
    /// Shows the system prompt the first time. Returns the answer.
    func requestMicrophoneAccess() async -> MicrophoneAccess

    /// Set by the session. Called when something else takes the audio (a call, Siri, another
    /// app) and recording has stopped capturing.
    var interruptionHandler: (@MainActor () -> Void)? { get set }

    /// The current input loudness, 0 (silent) to 1 (loud), for the waveform.
    var level: Float { get }

    /// Begins capturing a new recording. Async because activating the audio session can block,
    /// so it never runs on the main thread.
    func start(recordingID: UUID, startedAt: Date) async throws
    /// Stops capturing but keeps what's recorded so far.
    func pause()
    /// Carries on capturing into the same recording. Throws while the audio is still taken.
    func resume() async throws
    /// Ends capturing and returns the audio. The partial file stays until
    /// `removeRecordingFile(id:)`, so it can't be lost between stopping and saving.
    func stop() throws -> Data
    /// Ends capturing and deletes everything recorded.
    func discard()

    /// Recordings a crash or quit left behind, oldest first. Never includes one being recorded.
    func recoverPartialRecordings() -> [RecordedAudio]
    /// Deletes a recording's file once its memo is saved.
    func removeRecordingFile(id: UUID)
}
