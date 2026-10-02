import AVFoundation
import Foundation

/// Does the `AVAudioSession` work, which can block for a noticeable time, off the main thread.
private actor AudioSessionController {
    func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    func reactivate() throws {
        try AVAudioSession.sharedInstance().setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The real `AudioRecording`: records AAC, mono, 48 kbps with `AVAudioRecorder` into the app's
/// own `VoiceRecordings` folder, a file per recording plus a small JSON note of when it started.
/// The file is written as audio arrives, so a crash or quit leaves a partial recording for
/// `recoverPartialRecordings()`.
///
/// The container is CAF, not M4A: a CAF can be read after an unclean exit, while an M4A written
/// by `AVAudioRecorder` has no index until it's closed.
@MainActor
final class DeviceAudioRecorder: AudioRecording {
    enum RecorderError: Error {
        case couldNotStart
        case notRecording
    }

    var interruptionHandler: (@MainActor () -> Void)?

    private let directory: URL
    private var recorder: AVAudioRecorder?
    private var activeID: UUID?
    private let sessionController = AudioSessionController()
    /// The last deactivation, which the next recording waits for so they never overlap.
    private var pendingDeactivation: Task<Void, Never>?

    private struct Note: Codable {
        let startedAt: Date
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "VoiceRecordings", directoryHint: .isDirectory)
    }

    init(directory: URL = DeviceAudioRecorder.defaultDirectory) {
        self.directory = directory
        // The system deactivates the audio session when something else takes the audio: a call,
        // Siri, another app. The observer lives as long as the app does.
        _ = NotificationCenter.default.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionBecameInactive()
            }
        }
    }

    // MARK: Microphone access

    var microphoneAccess: MicrophoneAccess {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    func requestMicrophoneAccess() async -> MicrophoneAccess {
        await AVAudioApplication.requestRecordPermission() ? .granted : .denied
    }

    // MARK: Recording

    var level: Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        // Average power is -160...0 dB; speech sits roughly in -50...-5, so map that to 0...1.
        return max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 45))
    }

    func start(recordingID: UUID, startedAt: Date) async throws {
        await pendingDeactivation?.value
        try await sessionController.activateForRecording()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Note(startedAt: startedAt)).write(to: noteURL(recordingID), options: .atomic)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: audioURL(recordingID), settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
        activeID = recordingID
    }

    func pause() {
        recorder?.pause()
    }

    func resume() async throws {
        guard let recorder else { throw RecorderError.notRecording }
        try await sessionController.reactivate()
        guard recorder.record() else { throw RecorderError.couldNotStart }
    }

    func stop() throws -> Data {
        guard let recorder, let id = activeID else { throw RecorderError.notRecording }
        recorder.stop()
        endRecording()
        return try Data(contentsOf: audioURL(id))
    }

    func discard() {
        guard let recorder, let id = activeID else { return }
        recorder.stop()
        endRecording()
        removeRecordingFile(id: id)
    }

    // MARK: Recovery

    func recoverPartialRecordings() -> [RecordedAudio] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var recovered: [RecordedAudio] = []
        for url in urls where url.pathExtension == "caf" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), id != activeID else { continue }
            guard let duration = Self.duration(ofAudioAt: url), duration > 0, let data = try? Data(contentsOf: url) else {
                // Nothing playable was captured.
                removeRecordingFile(id: id)
                continue
            }
            recovered.append(RecordedAudio(id: id, startedAt: startDate(of: id, audioURL: url), duration: duration, data: data))
        }
        return recovered.sorted { $0.startedAt < $1.startedAt }
    }

    func removeRecordingFile(id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(id))
        try? FileManager.default.removeItem(at: noteURL(id))
    }

    // MARK: Private

    private func endRecording() {
        recorder = nil
        activeID = nil
        let controller = sessionController
        pendingDeactivation = Task { await controller.deactivate() }
    }

    private func sessionBecameInactive() {
        // Our own deactivation clears `recorder` first, so this is only ever someone else's.
        guard recorder != nil else { return }
        interruptionHandler?()
    }

    private func audioURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).caf", directoryHint: .notDirectory)
    }

    private func noteURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    private func startDate(of id: UUID, audioURL: URL) -> Date {
        if let data = try? Data(contentsOf: noteURL(id)), let note = try? JSONDecoder().decode(Note.self, from: data) {
            return note.startedAt
        }
        let values = try? audioURL.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? Date()
    }

    private static func duration(ofAudioAt url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        return rate > 0 ? Double(file.length) / rate : nil
    }
}
