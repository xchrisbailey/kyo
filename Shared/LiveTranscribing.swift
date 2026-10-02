import Foundation

/// The live-transcription seam: listens to the microphone while a **Voice memo** is being
/// recorded and reports what it hears, so the recorder can show it. The words are only for the
/// recorder; the memo's **Transcript** always comes from transcribing the saved audio. The real
/// one is `LiveSpeechTranscriber`.
@MainActor
protocol LiveTranscribing: AnyObject {
    /// Starts listening. Returns `false`, having started nothing, when live transcription isn't
    /// available (the model isn't installed or downloading, the language or device isn't
    /// supported, or another analysis is running). `onUpdate` receives everything heard since
    /// this call, finalized and still-changing words together, each time it changes.
    func start(onUpdate: @escaping @MainActor (String) -> Void) async -> Bool
    /// Stops listening and lets go of the microphone input and the speech model. Safe when
    /// nothing is running, and while a `start` is still pending, which then returns `false`.
    func stop()
}

/// Never transcribes live, so the recorder says "Transcript will appear after recording".
@MainActor
final class NoLiveTranscriber: LiveTranscribing {
    func start(onUpdate: @escaping @MainActor (String) -> Void) async -> Bool { false }
    func stop() {}
}
