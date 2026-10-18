import AVFoundation
import SwiftData
import XCTest

@MainActor
final class WatchStoreSelectionTests: XCTestCase {
    func testInMemoryLaunchKeepsRealCachesAndRecordingOutboxUntouched() throws {
        let suite = "kyo.watchLaunch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = WatchConnectivityTaskTransport(session: nil)
        let real = WatchStoreSelection.make(environment: [:], defaults: defaults,
            transport: { transport }, recordingDirectory: directory)
        let task = DailyTask(text: "Existing task", creationOrder: 0)
        let today = Date()
        let habit = Habit(name: "Existing habit", order: 0, createdOn: TaskCompletionDay(date: today, calendar: .current))
        let memo = WatchMemo(id: UUID(), day: TaskCompletionDay(date: today, calendar: .current),
            createdAt: today, kind: .written, title: "Existing memo")
        transport.receive(.init([
            WatchConnectivityTaskTransport.snapshotKey: try JSONEncoder().encode(TaskListSnapshot(revision: 1, tasks: [task])),
            WatchConnectivityTaskTransport.habitSnapshotKey: try JSONEncoder().encode(HabitListSnapshot(revision: 1, habits: [habit])),
            WatchConnectivityTaskTransport.memoSnapshotKey: try JSONEncoder().encode(MemoListSnapshot(revision: 1, memos: [memo]))
        ]))
        let audio = RecordedAudio(id: UUID(), startedAt: today, duration: 3, data: Data([1, 2, 3]))
        _ = try XCTUnwrap(real.memoList.outbox).saveVoiceMemo(audio, stoppedAtCap: false, photos: [])
        let isolated = WatchStoreSelection.make(environment: [KyoModelContainer.inMemoryEnvironmentKey: "1"],
            defaults: defaults, transport: { XCTFail("an isolated launch must not construct the live session"); return transport },
            recordingDirectory: directory)
        XCTAssertTrue(isolated.taskList.tasks.isEmpty)
        XCTAssertTrue(isolated.habitList.habits.isEmpty)
        XCTAssertTrue(isolated.memoList.listedMemos.isEmpty)
        _ = isolated.taskList.addTask(text: "Isolated task")
        _ = try XCTUnwrap(isolated.memoList.outbox).saveVoiceMemo(
            RecordedAudio(id: UUID(), startedAt: today, duration: 2, data: Data([4])), stoppedAtCap: false, photos: [])
        let reopened = WatchStoreSelection.make(environment: [:], defaults: defaults,
            transport: { WatchConnectivityTaskTransport(session: nil) }, recordingDirectory: directory)
        XCTAssertEqual(reopened.taskList.tasks, [task])
        XCTAssertEqual(reopened.habitList.habits, [habit])
        XCTAssertEqual(reopened.memoList.todayMemos, [memo])
        XCTAssertEqual(reopened.memoList.outbox?.entries.map(\.id), [audio.id])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("\(audio.id.uuidString).caf")), audio.data)
    }
    func testInMemoryCaptureDoesNotPopulateAnEmptyRealCache() throws {
        let suite = "kyo.watchCleanLaunch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let isolated = WatchStoreSelection.make(environment: [KyoModelContainer.inMemoryEnvironmentKey: "1"],
            defaults: defaults, transport: { XCTFail("no live connection during isolated capture"); return WatchConnectivityTaskTransport(session: nil) },
            recordingDirectory: directory)
        _ = isolated.taskList.addTask(text: "Isolated")
        _ = try XCTUnwrap(isolated.memoList.outbox).saveVoiceMemo(
            RecordedAudio(id: UUID(), startedAt: Date(), duration: 1, data: Data([1])), stoppedAtCap: false, photos: [])
        let real = WatchStoreSelection.make(environment: [:], defaults: defaults,
            transport: { WatchConnectivityTaskTransport(session: nil) }, recordingDirectory: directory)
        XCTAssertTrue(real.taskList.tasks.isEmpty)
        XCTAssertTrue(real.habitList.habits.isEmpty)
        XCTAssertTrue(real.memoList.listedMemos.isEmpty)
        XCTAssertTrue(try XCTUnwrap(real.memoList.outbox).entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    func testIsolatedStartupDoesNotConsumeInterruptedRecordingOrItsOriginalContext() async throws {
        let suite = "kyo.watchInterruptedLaunch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let originalDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17)))
        let metadataDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: originalDay))
        let container = try KyoModelContainer.make(inMemory: true)
        let memos = MemoStore(modelContainer: container, userDefaults: defaults)
        let projects = ProjectListStore(modelContainer: container,
            taskList: TaskListStore(userDefaults: defaults, modelContainer: container), memoStore: memos)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let microphone = FakeAudioRecorder()
        let interrupted = VoiceRecordingSession(recorder: microphone, memos: memos,
            now: { originalDay }, calendar: calendar, userDefaults: defaults)
        XCTAssertTrue(interrupted.selectProject(project.id))
        await interrupted.begin()
        let id = try XCTUnwrap(microphone.startedIDs.first)
        let audioURL = directory.appendingPathComponent("\(id.uuidString).caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        try XCTUnwrap(buffer.floatChannelData).pointee.initialize(repeating: 0, count: 8_000)
        do {
            let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            try file.write(from: buffer)
        }
        struct RecordingDate: Encodable { let startedAt: Date }
        try JSONEncoder().encode(RecordingDate(startedAt: metadataDay))
            .write(to: directory.appendingPathComponent("\(id.uuidString).json"))
        let audioBytes = try Data(contentsOf: audioURL)
        let isolated = WatchStoreSelection.make(environment: [KyoModelContainer.inMemoryEnvironmentKey: "1"],
            defaults: defaults, transport: { XCTFail("isolated recovery must not connect"); return WatchConnectivityTaskTransport(session: nil) },
            recordingDirectory: directory)
        let isolatedRecorder = WatchAudioRecorder(directory: try XCTUnwrap(isolated.isolatedRecordingDirectory))
        let isolatedSession = VoiceRecordingSession(recorder: isolatedRecorder, memos: try XCTUnwrap(isolated.memoList.outbox),
            userDefaults: isolated.recordingDefaults)
        XCTAssertTrue(isolatedSession.recoverInterruptedRecordings().isEmpty)
        XCTAssertEqual(try Data(contentsOf: audioURL), audioBytes)
        let realRecovery = VoiceRecordingSession(recorder: WatchAudioRecorder(directory: directory), memos: memos,
            calendar: calendar, userDefaults: defaults)
        let recovered = try XCTUnwrap(realRecovery.recoverInterruptedRecordings().first)
        XCTAssertEqual(recovered.id, id)
        XCTAssertEqual(recovered.projectID, project.id)
        XCTAssertEqual(recovered.day, TaskCompletionDay(date: originalDay, calendar: calendar),
            "the original saved context survives isolated startup")
        XCTAssertEqual(memos.audioData(forMemoID: id), audioBytes)
    }
}
