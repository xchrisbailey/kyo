import Combine
import Foundation

/// One **Voice memo** recording from permission to save. It keeps the elapsed time from a
/// controllable clock, shows the warning in the last 30 seconds, stops and saves at the
/// 10-minute cap, pauses when the audio is interrupted, and saves on **Stop** (never on
/// **Discard**). The views drive it: they call `tick()` while a recording is open.
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

    /// 10 minutes.
    static let cap: TimeInterval = 600
    /// The warning shows for this long before the cap.
    static let warningWindow: TimeInterval = 30
    /// How many recent levels the waveform keeps.
    static let waveformLength = 48

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// Recent input levels, 0 to 1, oldest first, for the waveform.
    @Published private(set) var levels: [Float] = []
    /// Set when a recording ends; cleared by `begin()`.
    @Published private(set) var outcome: Outcome?

    private let recorder: any AudioRecording
    private let memos: any MemoStoreBehavior
    private let now: () -> Date

    private var recordingID = UUID()
    private var startedAt = Date(timeIntervalSince1970: 0)
    /// Seconds recorded before the current stretch of recording.
    private var accumulated: TimeInterval = 0
    private var stretchStartedAt = Date(timeIntervalSince1970: 0)

    init(recorder: any AudioRecording, memos: any MemoStoreBehavior, now: @escaping () -> Date = Date.init) {
        self.recorder = recorder
        self.memos = memos
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
        elapsed = 0
        accumulated = 0
        levels = []
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
            try recorder.start(recordingID: id, startedAt: start)
        } catch {
            phase = .couldNotRecord
            return
        }
        recordingID = id
        startedAt = start
        stretchStartedAt = start
        phase = .recording
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
    func resume() {
        guard phase == .paused else { return }
        do {
            try recorder.resume()
        } catch {
            return
        }
        stretchStartedAt = now()
        phase = .recording
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
        recorder.discard()
        phase = .idle
        outcome = .discarded
    }

    /// Saves what a crash or quit left behind as Voice memos, each on the day it started.
    @discardableResult
    func recoverInterruptedRecordings() -> [Memo] {
        guard !isActive else { return [] }
        var recovered: [Memo] = []
        for audio in recorder.recoverPartialRecordings() {
            recovered.append(memos.addVoiceMemo(audio, stoppedAtCap: false))
            recorder.removeRecordingFile(id: audio.id)
        }
        return recovered
    }

    private func interrupted() {
        guard phase == .recording else { return }
        accumulated = min(accumulated + now().timeIntervalSince(stretchStartedAt), Self.cap)
        elapsed = accumulated
        recorder.pause()
        phase = .paused
    }

    private func finishAndSave(reachedCap: Bool) {
        let duration = elapsed
        let data: Data
        do {
            data = try recorder.stop()
        } catch {
            // The partial file stays on disk, so the next launch recovers it.
            phase = .couldNotRecord
            return
        }
        let memo = memos.addVoiceMemo(
            RecordedAudio(id: recordingID, startedAt: startedAt, duration: duration, data: data),
            stoppedAtCap: reachedCap
        )
        recorder.removeRecordingFile(id: recordingID)
        phase = .idle
        outcome = .saved(memo, reachedCap: reachedCap)
    }
}
