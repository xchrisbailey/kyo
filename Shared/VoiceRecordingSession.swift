import Combine
import Foundation

/// Where a finished recording goes: the phone's memo store, or the Watch's outbox (ADR 0005).
@MainActor
protocol VoiceMemoSaving: AnyObject {
    /// Saves `audio` as a Voice memo, on the day recording started. Throws
    /// `AudioRecordingError.outOfSpace` when there's no room, saving nothing.
    @discardableResult
    func saveVoiceMemo(_ audio: RecordedAudio, stoppedAtCap: Bool, photos: [StoredPhoto]) throws -> Memo
}

extension VoiceMemoSaving where Self: MemoStoreBehavior {
    @discardableResult
    func saveVoiceMemo(_ audio: RecordedAudio, stoppedAtCap: Bool, photos: [StoredPhoto]) throws -> Memo {
        addVoiceMemo(audio, stoppedAtCap: stoppedAtCap, photos: photos)
    }
}

/// One **Voice memo** recording from permission to save. It keeps the elapsed time from a
/// controllable clock, shows the warning in the last 30 seconds, stops and saves at the
/// 10-minute cap, pauses when the audio is interrupted, and saves on **Stop** (never on
/// **Discard**). The views drive it: they call `tick()` while a recording is open.
///
/// Photos taken while recording wait here, up to 4, and go with the memo when it's saved; a
/// **Discard** drops them.
///
/// While recording it also runs live transcription through the `LiveTranscribing` seam, for the
/// recorder to show. Live transcription never gates recording: if it isn't available, recording
/// goes on and the recorder says the transcript will appear after recording.
@MainActor
final class VoiceRecordingSession: ObservableObject {
    enum Phase: Equatable {
        /// Not recording: before `begin()` and after a recording ended.
        case idle
        /// Waiting for the microphone prompt.
        case starting
        case recording
        /// Interrupted: **Paused**, with **Resume** and **Stop**.
        case paused
        /// Microphone access is denied; nothing is recorded or saved.
        case microphoneDenied
        /// The recorder couldn't start; nothing is recorded or saved.
        case couldNotRecord
    }

    enum Outcome: Equatable {
        case saved(Memo, reachedCap: Bool)
        case discarded
    }

    /// Whether the recorder can show a live transcript.
    enum LiveStatus: Equatable {
        /// Waiting to hear whether live transcription started.
        case starting
        case listening
        /// "Transcript will appear after recording".
        case unavailable
    }

    /// 10 minutes.
    static let cap: TimeInterval = 600
    /// The warning shows for this long before the cap.
    static let warningWindow: TimeInterval = 30
    /// How many recent levels the waveform keeps.
    static let waveformLength = 48

    /// Why the recorder is in `couldNotRecord`.
    enum Failure: Equatable {
        /// The device has no room: the Watch's "Not enough space on Apple Watch".
        case outOfSpace
        case other
    }

    @Published private(set) var phase: Phase = .idle
    /// Set with `couldNotRecord`; `nil` otherwise.
    @Published private(set) var failure: Failure?
    @Published private(set) var elapsed: TimeInterval = 0
    /// Recent input levels, 0 to 1, oldest first, for the waveform.
    @Published private(set) var levels: [Float] = []
    /// Set when a recording ends; cleared by `begin()`.
    @Published private(set) var outcome: Outcome?
    @Published private(set) var liveStatus: LiveStatus = .starting
    /// What live transcription has heard so far, kept across a pause. Only for the recorder: the
    /// saved memo's Transcript comes from transcribing its audio.
    @Published private(set) var liveTranscript = ""
    /// Photos attached to the recording so far, oldest first. Cleared when a recording begins.
    @Published private(set) var photos: [StoredPhoto] = []

    private let recorder: any AudioRecording
    private let memos: any VoiceMemoSaving
    private let live: any LiveTranscribing
    private let now: () -> Date

    private var recordingID = UUID()
    private var startedAt = Date(timeIntervalSince1970: 0)
    /// Seconds recorded before the current stretch of recording.
    private var accumulated: TimeInterval = 0
    private var stretchStartedAt = Date(timeIntervalSince1970: 0)
    private var isResuming = false
    /// Text heard before the current stretch of live transcription (before a pause).
    private var liveBase = ""
    /// Tells a live transcription that has been stopped apart from the one now running.
    private var liveGeneration = 0

    init(
        recorder: any AudioRecording,
        memos: any VoiceMemoSaving,
        live: any LiveTranscribing = NoLiveTranscriber(),
        now: @escaping () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.memos = memos
        self.live = live
        self.now = now
        recorder.interruptionHandler = { [weak self] in self?.interrupted() }
    }

    /// `true` from the start of a recording until it ends.
    var isActive: Bool {
        phase == .recording || phase == .paused
    }

    var remaining: TimeInterval {
        max(0, Self.cap - elapsed)
    }

    /// `true` in the last 30 seconds before the cap.
    var isNearCap: Bool {
        isActive && remaining <= Self.warningWindow
    }

    /// Asks for the microphone if needed, then starts recording on the current day.
    func begin() async {
        guard phase == .idle || phase == .microphoneDenied || phase == .couldNotRecord else { return }
        outcome = nil
        failure = nil
        elapsed = 0
        accumulated = 0
        levels = []
        liveStatus = .starting
        liveTranscript = ""
        liveBase = ""
        photos = []
        phase = .starting

        var access = recorder.microphoneAccess
        if access == .undetermined {
            access = await recorder.requestMicrophoneAccess()
        }
        guard access == .granted else {
            phase = .microphoneDenied
            return
        }

        let id = UUID()
        let start = now()
        do {
            try await recorder.start(recordingID: id, startedAt: start)
        } catch {
            fail(because: error)
            return
        }
        recordingID = id
        startedAt = start
        stretchStartedAt = start
        phase = .recording
        startLive()
    }

    /// Advances the elapsed time and the waveform, and ends the recording at the cap.
    func tick() {
        guard phase == .recording else { return }
        elapsed = min(accumulated + now().timeIntervalSince(stretchStartedAt), Self.cap)
        levels.append(recorder.level)
        if levels.count > Self.waveformLength {
            levels.removeFirst(levels.count - Self.waveformLength)
        }
        if elapsed >= Self.cap {
            finishAndSave(reachedCap: true)
        }
    }

    /// Carries on from **Paused**, from the elapsed time it stopped at. Stays paused if the
    /// audio is still taken.
    func resume() async {
        guard phase == .paused, !isResuming else { return }
        isResuming = true
        defer { isResuming = false }
        do {
            try await recorder.resume()
        } catch {
            return
        }
        // Stopped, discarded or interrupted again while the audio session was waking up.
        guard phase == .paused else {
            recorder.pause()
            return
        }
        stretchStartedAt = now()
        phase = .recording
        // A recording whose live transcription never started doesn't try again.
        if liveStatus != .unavailable { startLive() }
    }

    /// Attaches a photo to the recording. Returns `false` when there are already 4, or no
    /// recording is under way.
    @discardableResult
    func addPhoto(_ photo: StoredPhoto) -> Bool {
        guard isActive, photos.count < Memo.maximumPhotos else { return false }
        if !photos.contains(where: { $0.id == photo.id }) { photos.append(photo) }
        return true
    }

    func removePhoto(id: UUID) {
        photos.removeAll { $0.id == id }
    }

    /// **Stop**: saves the recording as a Voice memo.
    func stop() {
        guard isActive else { return }
        if phase == .recording { tick() }
        // `tick()` already saved the recording when it reached the cap.
        guard isActive else { return }
        finishAndSave(reachedCap: false)
    }

    /// **Discard**: saves nothing.
    func discard() {
        guard isActive else { return }
        stopLive()
        recorder.discard()
        photos = []
        phase = .idle
        outcome = .discarded
    }

    /// Saves what a crash or quit left behind as Voice memos, each on the day it started.
    @discardableResult
    func recoverInterruptedRecordings() -> [Memo] {
        guard !isActive else { return [] }
        var recovered: [Memo] = []
        for audio in recorder.recoverPartialRecordings() {
            // Out of space: the file stays, and the next launch tries again.
            guard let memo = try? memos.saveVoiceMemo(audio, stoppedAtCap: false, photos: []) else { continue }
            recovered.append(memo)
            recorder.removeRecordingFile(id: audio.id)
        }
        return recovered
    }

    // MARK: Live transcription

    private func startLive() {
        liveGeneration += 1
        let generation = liveGeneration
        Task { [weak self] in
            guard let self else { return }
            let started = await self.live.start { [weak self] heard in
                guard let self, generation == self.liveGeneration else { return }
                self.liveTranscript = Self.joined(self.liveBase, heard)
            }
            // Recording ended or paused while this was starting.
            guard generation == self.liveGeneration else { return }
            self.liveStatus = started ? .listening : .unavailable
        }
    }

    /// Stops listening, keeping what was heard so a resume carries on after it.
    private func stopLive() {
        liveGeneration += 1
        live.stop()
        liveBase = liveTranscript
    }

    private static func joined(_ base: String, _ heard: String) -> String {
        let trimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return trimmed }
        return trimmed.isEmpty ? base : base + " " + trimmed
    }

    private func interrupted() {
        guard phase == .recording else { return }
        accumulated = min(accumulated + now().timeIntervalSince(stretchStartedAt), Self.cap)
        elapsed = accumulated
        stopLive()
        recorder.pause()
        phase = .paused
    }

    private func fail(because error: any Error) {
        failure = (error as? AudioRecordingError) == .outOfSpace ? .outOfSpace : .other
        phase = .couldNotRecord
    }

    private func finishAndSave(reachedCap: Bool) {
        let duration = elapsed
        stopLive()
        let data: Data
        do {
            data = try recorder.stop()
        } catch {
            // The partial file stays on disk, so the next launch recovers it.
            fail(because: error)
            return
        }
        let memo: Memo
        do {
            memo = try memos.saveVoiceMemo(
                RecordedAudio(id: recordingID, startedAt: startedAt, duration: duration, data: data),
                stoppedAtCap: reachedCap,
                photos: photos
            )
        } catch {
            // No room: nothing is saved, so the partial file doesn't come back as a memo later.
            recorder.removeRecordingFile(id: recordingID)
            fail(because: error)
            return
        }
        recorder.removeRecordingFile(id: recordingID)
        phase = .idle
        outcome = .saved(memo, reachedCap: reachedCap)
    }
}
