import SwiftData
import XCTest

@MainActor
final class ProjectMemoBehaviorTests: XCTestCase {
    func testAssignmentSwitchAndRemovalKeepOneMemoInDayHistoryAndProjectLists() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let memos = MemoStore(modelContainer: container)
        let projects: any ProjectListBehavior = ProjectListStore(modelContainer: container,
            taskList: TaskListStore(modelContainer: container), memoStore: memos)
        let first = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let second = try XCTUnwrap(projects.createProject(name: "House"))
        let memo = try XCTUnwrap(memos.addWrittenMemo(text: "Original thought"))
        XCTAssertNil(memos.assignMemo(id: memo.id, to: UUID()))
        let assigned = try XCTUnwrap(memos.assignMemo(id: memo.id, to: first.id))
        XCTAssertEqual(assigned.projectID, first.id)
        XCTAssertEqual(projects.memos(in: first.id), [assigned])
        XCTAssertEqual(memos.memos(on: memo.createdAt), [assigned])
        _ = memos.assignMemo(id: memo.id, to: second.id)
        XCTAssertTrue(projects.memos(in: first.id).isEmpty)
        XCTAssertEqual(projects.memos(in: second.id).map(\.id), [memo.id])
        let removed = try XCTUnwrap(memos.assignMemo(id: memo.id, to: nil))
        XCTAssertEqual(removed, memo)
        XCTAssertEqual(memos.memos, [memo])
        XCTAssertTrue(projects.memos(in: second.id).isEmpty)
    }
    func testRecoveredRecordingKeepsArchivedProjectAndOriginalDayAcrossTimeZoneChange() async throws {
        let container = try KyoModelContainer.make(inMemory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -7 * 3600))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23)))
        let originalDay = TaskCompletionDay(era: 1, year: 2026, month: 10, day: 12)
        let memos = MemoStore(modelContainer: container, now: { start }, calendar: calendar)
        let projects = ProjectListStore(modelContainer: container, taskList: TaskListStore(modelContainer: container), memoStore: memos)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let suite = "ProjectMemoRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = FakeAudioRecorder()
        let session = VoiceRecordingSession(recorder: recorder, memos: memos, now: { start }, calendar: calendar, userDefaults: defaults)
        session.selectProject(project.id)
        await session.begin()
        _ = projects.archiveProject(id: project.id)
        XCTAssertFalse(session.selectProject(UUID()))
        XCTAssertEqual(session.projectID, project.id)
        let id = try XCTUnwrap(recorder.startedIDs.first)
        recorder.partialRecordings = [RecordedAudio(id: id, startedAt: start, duration: 4, data: Data([7, 8]))]
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3600))
        let recoveredStore = MemoStore(modelContainer: container, now: { start }, calendar: calendar)
        let recoveredSession = VoiceRecordingSession(recorder: recorder, memos: recoveredStore, calendar: calendar, userDefaults: defaults)
        let recovered = try XCTUnwrap(recoveredSession.recoverInterruptedRecordings().first)
        XCTAssertEqual(recovered.id, id)
        XCTAssertEqual(recovered.day, originalDay)
        XCTAssertEqual(recovered.projectID, project.id)
        XCTAssertEqual(recoveredStore.audioData(forMemoID: id), Data([7, 8]))
        XCTAssertTrue(recoveredSession.recoverInterruptedRecordings().isEmpty)
    }

    func testArchiveDuringBackgroundTranscriptionPreservesAssignmentMediaAndDayVisibility() async throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let transcriber = ScriptedTranscriber()
        let memos = MemoStore(modelContainer: container, now: { today }, calendar: calendar, transcriber: transcriber)
        let projects = ProjectListStore(modelContainer: container, taskList: TaskListStore(modelContainer: container), memoStore: memos)
        let first = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let second = try XCTUnwrap(projects.createProject(name: "House"))
        let photo = StoredPhoto(data: Data([1, 2]), thumbnail: Data([3]))
        XCTAssertNil(memos.addWrittenMemo(text: "Orphan", photos: [], projectID: UUID()))
        let written = try XCTUnwrap(memos.addWrittenMemo(text: "Capture", photos: [photo], projectID: first.id))
        let audio = RecordedAudio(id: UUID(), startedAt: today.addingTimeInterval(5), duration: 3, data: Data([4, 5]))
        let context = RecordingMemoContext(day: TaskCompletionDay(date: today, calendar: calendar), projectID: first.id)
        let voice = try memos.saveVoiceMemo(audio, stoppedAtCap: true, photos: [photo], context: context)
        _ = memos.assignMemo(id: voice.id, to: second.id)
        _ = memos.renameMemo(id: voice.id, title: "Chosen title")
        _ = projects.archiveProject(id: second.id)
        transcriber.release(.transcript("Transcript arrived"))
        for _ in 0..<100 where memos.memo(id: voice.id)?.transcriptState != .transcribed {
            try await Task.sleep(for: .milliseconds(10))
        }
        let updated = try XCTUnwrap(memos.memo(id: voice.id))
        XCTAssertEqual(updated.projectID, second.id)
        XCTAssertEqual(updated.day, context.day)
        XCTAssertEqual(updated.createdAt, audio.startedAt)
        XCTAssertEqual(updated.text, "Transcript arrived")
        XCTAssertEqual(updated.title, "Chosen title")
        XCTAssertEqual(updated.photoIDs, [photo.id])
        XCTAssertEqual(memos.audioData(forMemoID: audio.id), audio.data)
        XCTAssertEqual(memos.photoData(forPhotoID: photo.id), photo.data)
        XCTAssertEqual(try memos.saveVoiceMemo(audio, stoppedAtCap: true, photos: [], context: context), updated)
        XCTAssertEqual(projects.memos(in: first.id), [written])
        XCTAssertEqual(projects.memos(in: second.id), [updated])
        XCTAssertEqual(memos.memos(on: today).map(\.id), [voice.id, written.id])
        XCTAssertEqual(memos.daysWithMemos(from: today, through: today), [today])
        let month = try XCTUnwrap(MemoMonthContent(store: memos).content(on: [today])[today])
        XCTAssertEqual(month.phrase, "2 memos")
        XCTAssertEqual(month.rows.map(\.target), [.memo(voice.id), .memo(written.id)])
        XCTAssertEqual(memos.memoGroups(matching: "arrived", limit: 50).groups.flatMap(\.results).map(\.id), [voice.id])
    }

    func testArchiveSurvivesDelayedTitleAndPhotoChangesWithoutChangingWatchSnapshot() async throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let model = FakeOnDeviceLanguageModel(availability: .available)
        model.titleAnswer = .title("Generated title")
        model.holdsTitleRequest = true
        let transcriber = ScriptedTranscriber()
        let transport = ControllableMemoTransport()
        let suite = "ProjectMemoSnapshot.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoStore(modelContainer: container, now: { today }, calendar: calendar,
            transcriber: transcriber, languageModel: model, memoSync: transport, userDefaults: defaults)
        let projects = ProjectListStore(modelContainer: container, taskList: TaskListStore(modelContainer: container), memoStore: store)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let audio = RecordedAudio(id: UUID(), startedAt: today, duration: 3, data: Data([4]))
        let original = store.addVoiceMemo(audio, stoppedAtCap: false)
        transcriber.release(.transcript("Recognized text"))
        for _ in 0..<100 where model.receivedTitleTexts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.receivedTitleTexts.isEmpty)
        let snapshot = try XCTUnwrap(transport.published.last)
        _ = projects.archiveProject(id: project.id)
        _ = store.assignMemo(id: original.id, to: project.id)
        XCTAssertEqual(transport.published.last, snapshot)
        let photo = StoredPhoto(data: Data([5]), thumbnail: Data([6]))
        _ = store.addPhoto(photo, toMemoID: original.id)
        model.finishPendingTitleRequest()
        await store.transcriptionsSettled()
        let updated = try XCTUnwrap(store.memo(id: original.id))
        XCTAssertEqual(updated.projectID, project.id)
        XCTAssertEqual(updated.title, "Generated title")
        XCTAssertEqual(updated.photoIDs, [photo.id])
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.day, original.day)
        XCTAssertEqual(transport.published.last?.memos.map(\.id), [original.id])
        _ = store.removePhoto(id: photo.id, fromMemoID: original.id)
        XCTAssertEqual(store.memo(id: original.id)?.projectID, project.id)
    }

}
