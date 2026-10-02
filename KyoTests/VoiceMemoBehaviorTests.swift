import SwiftData
import XCTest

/// Behavior of **Voice memos**: recording through `VoiceRecordingSession` with a fake recorder and
/// a controlled clock, and the saved memos through `MemoStoreBehavior`, on an in-memory store.
@MainActor
final class VoiceMemoBehaviorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// A clock the tests move by hand, shared by the store and the session.
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private struct Fixture {
        let container: ModelContainer
        let clock: Clock
        let recorder: FakeAudioRecorder
        let store: MemoStore
        let session: VoiceRecordingSession
    }

    /// September 2026, UTC.
    private func moment(_ day: Int, _ hour: Int = 9, _ minute: Int = 0, _ second: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second
        )))
    }

    private func makeFixture(
        at start: Date? = nil,
        access: MicrophoneAccess = .granted,
        transcriber: any VoiceTranscriber = NoTranscriber(),
        container: ModelContainer? = nil
    ) throws -> Fixture {
        let clock = Clock(try start ?? moment(29, 9, 41))
        let container = try container ?? KyoModelContainer.make(inMemory: true)
        let recorder = FakeAudioRecorder(access: access)
        let store = MemoStore(
            modelContainer: container,
            now: { clock.now },
            calendar: calendar,
            transcriber: transcriber
        )
        let session = VoiceRecordingSession(recorder: recorder, memos: store, now: { clock.now })
        return Fixture(container: container, clock: clock, recorder: recorder, store: store, session: session)
    }

    private func recordSeconds(_ seconds: TimeInterval, _ fixture: Fixture) {
        fixture.clock.advance(seconds)
        fixture.session.tick()
    }

    private func savedMemo(_ session: VoiceRecordingSession, file: StaticString = #filePath, line: UInt = #line) throws -> Memo {
        guard case .saved(let memo, _)? = session.outcome else {
            XCTFail("Expected a saved voice memo, got \(String(describing: session.outcome))", file: file, line: line)
            throw XCTSkip("no saved memo")
        }
        return memo
    }

    // MARK: Saving on Stop

    func testStoppingSavesAVoiceMemoWithItsAudioDurationAndTime() async throws {
        let f = try makeFixture(at: try moment(29, 9, 41))
        await f.session.begin()
        XCTAssertEqual(f.session.phase, .recording)

        recordSeconds(42, f)
        f.session.stop()

        let memo = try savedMemo(f.session)
        XCTAssertEqual(f.store.memos, [memo])
        XCTAssertEqual(memo.kind, .voice)
        XCTAssertEqual(memo.title, "Voice memo")
        XCTAssertEqual(memo.duration, 42)
        XCTAssertEqual(memo.createdAt, try moment(29, 9, 41))
        XCTAssertFalse(memo.stoppedAtCap)
        XCTAssertNil(memo.capNote)
        XCTAssertEqual(f.store.audioData(forMemoID: memo.id), f.recorder.recordedBytes)
        XCTAssertEqual(f.session.phase, .idle)
        XCTAssertFalse(f.recorder.isCapturing)
        XCTAssertEqual(f.recorder.removedFileIDs, [memo.id])
    }

    func testTheMemoIsSavedAsSoonAsRecordingStopsInTheTranscribingState() async throws {
        let transcriber = ScriptedTranscriber()
        let f = try makeFixture(transcriber: transcriber)
        await f.session.begin()
        recordSeconds(5, f)

        f.session.stop()

        let memo = try savedMemo(f.session)
        XCTAssertEqual(memo.transcriptState, .transcribing)
        XCTAssertEqual(memo.detail, "Transcribing…")
        XCTAssertEqual(f.store.memos.first?.transcriptState, .transcribing)
        transcriber.release(.noSpeech)
        await f.store.transcriptionsSettled()
    }

    func testWithoutATranscriberANewVoiceMemoEndsAsNoTranscriptAndKeepsItsAudio() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(8, f)
        f.session.stop()
        let id = try savedMemo(f.session).id

        await f.store.transcriptionsSettled()

        let memo = try XCTUnwrap(f.store.memo(id: id))
        XCTAssertEqual(memo.transcriptState, .noTranscript)
        XCTAssertEqual(memo.detail, "No transcript")
        XCTAssertEqual(memo.text, "")
        XCTAssertEqual(f.store.audioData(forMemoID: id), f.recorder.recordedBytes)
    }

    func testAVoiceMemoBelongsToTheDayRecordingStarted() async throws {
        let f = try makeFixture(at: try moment(28, 23, 59, 30))
        await f.session.begin()

        recordSeconds(120, f)
        f.session.stop()

        let memo = try savedMemo(f.session)
        XCTAssertEqual(memo.day, TaskCompletionDay(era: 1, year: 2026, month: 9, day: 28))
        XCTAssertEqual(memo.createdAt, try moment(28, 23, 59, 30))
        // It's now the 29th, so the memo lives in history, not on Today.
        XCTAssertTrue(f.store.memos.isEmpty)
        XCTAssertEqual(f.store.memo(id: memo.id)?.day, memo.day)
    }

    func testVoiceAndWrittenMemosShareTodayNewestFirst() async throws {
        let f = try makeFixture(at: try moment(29, 8))
        _ = f.store.addWrittenMemo(text: "Morning note")
        f.clock.advance(3600)
        await f.session.begin()
        recordSeconds(10, f)
        f.session.stop()

        XCTAssertEqual(f.store.memos.map(\.title), ["Voice memo", "Morning note"])
        XCTAssertEqual(f.store.sectionSubtitle, "2 memos")
    }

    // MARK: Discard

    func testDiscardingSavesNothing() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(30, f)

        f.session.discard()

        XCTAssertEqual(f.session.outcome, .discarded)
        XCTAssertEqual(f.session.phase, .idle)
        XCTAssertEqual(f.recorder.discardCount, 1)
        XCTAssertTrue(f.store.memos.isEmpty)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 0)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoAudioRecord>()), 0)
    }

    func testDiscardingWhilePausedSavesNothing() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(30, f)
        f.recorder.simulateInterruption()

        f.session.discard()

        XCTAssertTrue(f.store.memos.isEmpty)
        XCTAssertEqual(f.session.outcome, .discarded)
    }

    // MARK: Elapsed time, waveform and the cap

    func testTheElapsedTimeFollowsTheClockAndTheWaveformKeepsRecentLevels() async throws {
        let f = try makeFixture()
        await f.session.begin()

        for step in 1...(VoiceRecordingSession.waveformLength + 10) {
            f.recorder.level = Float(step % 10) / 10
            recordSeconds(1, f)
        }

        XCTAssertEqual(f.session.elapsed, TimeInterval(VoiceRecordingSession.waveformLength + 10))
        XCTAssertEqual(f.session.levels.count, VoiceRecordingSession.waveformLength)
        XCTAssertEqual(f.session.levels.last, Float((VoiceRecordingSession.waveformLength + 10) % 10) / 10)
    }

    func testTheCapWarningShowsInTheLast30Seconds() async throws {
        let f = try makeFixture()
        await f.session.begin()

        recordSeconds(569, f)
        XCTAssertFalse(f.session.isNearCap)

        recordSeconds(1, f)
        XCTAssertTrue(f.session.isNearCap)
        XCTAssertEqual(f.session.remaining, 30)

        recordSeconds(20, f)
        XCTAssertTrue(f.session.isNearCap)
        XCTAssertEqual(f.session.remaining, 10)
        XCTAssertEqual(f.session.phase, .recording)
    }

    func testRecordingStopsAndSavesAtTenMinutesWithTheCapNote() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(599, f)
        XCTAssertEqual(f.session.phase, .recording)

        recordSeconds(1, f)

        guard case .saved(let memo, let reachedCap)? = f.session.outcome else {
            return XCTFail("Expected the recording to stop and save at the cap")
        }
        XCTAssertTrue(reachedCap)
        XCTAssertEqual(memo.duration, 600)
        XCTAssertTrue(memo.stoppedAtCap)
        XCTAssertEqual(memo.capNote, "Recording stopped at 10 minutes")
        XCTAssertEqual(f.store.memos, [memo])
        XCTAssertEqual(f.session.phase, .idle)
        XCTAssertFalse(f.recorder.isCapturing)
    }

    func testALateTickPastTheCapStillSavesExactlyTenMinutes() async throws {
        let f = try makeFixture()
        await f.session.begin()

        recordSeconds(640, f)

        XCTAssertEqual(try savedMemo(f.session).duration, 600)
        XCTAssertEqual(f.store.memos.count, 1)
    }

    func testTheCapNoteSurvivesReopeningTheStore() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(600, f)
        let id = try savedMemo(f.session).id

        let reopened = MemoStore(modelContainer: f.container, now: { f.clock.now }, calendar: calendar)

        XCTAssertEqual(reopened.memo(id: id)?.capNote, "Recording stopped at 10 minutes")
    }

    func testStoppingBeforeTheCapHasNoCapNote() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(599, f)

        f.session.stop()

        XCTAssertNil(try savedMemo(f.session).capNote)
    }

    // MARK: Interruptions

    func testAnInterruptionPausesAndTheElapsedTimeStopsCounting() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(60, f)

        f.recorder.simulateInterruption()
        f.clock.advance(300)
        f.session.tick()

        XCTAssertEqual(f.session.phase, .paused)
        XCTAssertEqual(f.session.elapsed, 60)
        XCTAssertTrue(f.store.memos.isEmpty)
    }

    func testResumingCarriesOnFromWhereItPaused() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(60, f)
        f.recorder.simulateInterruption()
        f.clock.advance(300)

        await f.session.resume()
        XCTAssertEqual(f.session.phase, .recording)
        XCTAssertTrue(f.recorder.isCapturing)
        recordSeconds(15, f)

        XCTAssertEqual(f.session.elapsed, 75)
    }

    func testStoppingWhilePausedSavesWhatWasRecorded() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(60, f)
        f.recorder.simulateInterruption()
        f.clock.advance(300)

        f.session.stop()

        XCTAssertEqual(try savedMemo(f.session).duration, 60)
        XCTAssertEqual(f.store.memos.count, 1)
    }

    func testTheCapCarriesOverAPause() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(300, f)
        f.recorder.simulateInterruption()
        f.clock.advance(1000)
        await f.session.resume()

        recordSeconds(299, f)
        XCTAssertEqual(f.session.phase, .recording)
        XCTAssertTrue(f.session.isNearCap)
        recordSeconds(1, f)

        guard case .saved(let memo, true)? = f.session.outcome else {
            return XCTFail("Expected the cap to stop the recording at 10:00 of recorded time")
        }
        XCTAssertEqual(memo.duration, 600)
    }

    func testResumingWhileTheAudioIsStillTakenStaysPaused() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(20, f)
        f.recorder.simulateInterruption()
        f.recorder.isAudioTaken = true

        await f.session.resume()
        XCTAssertEqual(f.session.phase, .paused)

        f.recorder.isAudioTaken = false
        await f.session.resume()
        XCTAssertEqual(f.session.phase, .recording)
    }

    func testAnInterruptionWhileNotRecordingChangesNothing() async throws {
        let f = try makeFixture()

        f.recorder.simulateInterruption()

        XCTAssertEqual(f.session.phase, .idle)
    }

    // MARK: Microphone permission

    func testFirstUseAsksForMicrophoneAccessThenRecords() async throws {
        let f = try makeFixture(access: .undetermined)
        f.recorder.promptAnswer = .granted

        await f.session.begin()

        XCTAssertEqual(f.recorder.promptCount, 1)
        XCTAssertEqual(f.session.phase, .recording)
        XCTAssertTrue(f.recorder.isCapturing)
    }

    func testDecliningThePromptShowsTheDeniedStateAndSavesNothing() async throws {
        let f = try makeFixture(access: .undetermined)
        f.recorder.promptAnswer = .denied

        await f.session.begin()

        XCTAssertEqual(f.session.phase, .microphoneDenied)
        XCTAssertTrue(f.recorder.startedIDs.isEmpty)
        XCTAssertTrue(f.store.memos.isEmpty)
    }

    func testDeniedAccessDoesNotPromptAgainAndSavesNothing() async throws {
        let f = try makeFixture(access: .denied)

        await f.session.begin()
        f.session.stop()

        XCTAssertEqual(f.recorder.promptCount, 0)
        XCTAssertEqual(f.session.phase, .microphoneDenied)
        XCTAssertNil(f.session.outcome)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 0)
    }

    func testRecordingStartsOnceAccessIsAllowedInSettings() async throws {
        let f = try makeFixture(access: .denied)
        await f.session.begin()
        XCTAssertEqual(f.session.phase, .microphoneDenied)

        f.recorder.microphoneAccess = .granted
        await f.session.begin()

        XCTAssertEqual(f.session.phase, .recording)
    }

    func testARecorderThatCantStartSavesNothing() async throws {
        let f = try makeFixture()
        f.recorder.startError = FakeAudioRecorder.StartFailure()

        await f.session.begin()

        XCTAssertEqual(f.session.phase, .couldNotRecord)
        XCTAssertTrue(f.store.memos.isEmpty)
    }

    func testBeginningWhileRecordingDoesNotStartASecondRecording() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(10, f)

        await f.session.begin()

        XCTAssertEqual(f.recorder.startedIDs.count, 1)
        XCTAssertEqual(f.session.elapsed, 10)
    }

    func testASecondRecordingStartsCleanAfterTheFirstEnded() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(90, f)
        f.session.stop()

        await f.session.begin()

        XCTAssertEqual(f.session.phase, .recording)
        XCTAssertEqual(f.session.elapsed, 0)
        XCTAssertNil(f.session.outcome)
        XCTAssertTrue(f.session.levels.isEmpty)
        recordSeconds(7, f)
        f.session.stop()
        XCTAssertEqual(f.store.memos.map(\.duration), [7, 90])
    }

    func testAFailedStopKeepsTheRecordingForRecoveryInsteadOfLosingIt() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(10, f)
        f.recorder.stopError = FakeAudioRecorder.StopFailure()

        f.session.stop()

        XCTAssertEqual(f.session.phase, .couldNotRecord)
        XCTAssertTrue(f.store.memos.isEmpty)
        XCTAssertEqual(f.recorder.discardCount, 0)
        XCTAssertTrue(f.recorder.removedFileIDs.isEmpty)
    }

    // MARK: Crash and quit recovery

    func testPartialRecordingsLeftByACrashAreSavedAsVoiceMemos() async throws {
        let f = try makeFixture(at: try moment(29, 14))
        let started = try moment(29, 13, 30)
        let partial = RecordedAudio(id: UUID(), startedAt: started, duration: 95, data: Data([9, 9]))
        f.recorder.partialRecordings = [partial]

        let recovered = f.session.recoverInterruptedRecordings()

        XCTAssertEqual(recovered.map(\.id), [partial.id])
        let memo = try XCTUnwrap(f.store.memo(id: partial.id))
        XCTAssertEqual(memo.kind, .voice)
        XCTAssertEqual(memo.duration, 95)
        XCTAssertEqual(memo.createdAt, started)
        XCTAssertEqual(f.store.memos, [memo])
        XCTAssertEqual(f.store.audioData(forMemoID: partial.id), Data([9, 9]))
        XCTAssertEqual(f.recorder.removedFileIDs, [partial.id])
        // Transcription starts for it like any other Voice memo.
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: partial.id)?.transcriptState, .noTranscript)
    }

    func testARecoveredRecordingKeepsTheDayItStarted() async throws {
        let f = try makeFixture(at: try moment(30, 8))
        let partial = RecordedAudio(id: UUID(), startedAt: try moment(29, 23, 50), duration: 400, data: Data([1]))
        f.recorder.partialRecordings = [partial]

        f.session.recoverInterruptedRecordings()

        XCTAssertEqual(f.store.memo(id: partial.id)?.day, TaskCompletionDay(era: 1, year: 2026, month: 9, day: 29))
        XCTAssertTrue(f.store.memos.isEmpty)
    }

    func testRecoveringTwiceNeverDuplicatesAMemo() async throws {
        let f = try makeFixture()
        let partial = RecordedAudio(id: UUID(), startedAt: try moment(29, 9), duration: 12, data: Data([1]))
        f.recorder.partialRecordings = [partial]
        f.session.recoverInterruptedRecordings()
        // The file removal was lost, as when the app quit between saving and removing.
        f.recorder.partialRecordings = [partial]

        f.session.recoverInterruptedRecordings()

        XCTAssertEqual(f.store.memos.count, 1)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoAudioRecord>()), 1)
    }

    func testNothingIsRecoveredWhileARecordingIsRunning() async throws {
        let f = try makeFixture()
        await f.session.begin()
        f.recorder.partialRecordings = [RecordedAudio(id: UUID(), startedAt: try moment(29, 9), duration: 3, data: Data([1]))]

        XCTAssertTrue(f.session.recoverInterruptedRecordings().isEmpty)
        XCTAssertTrue(f.store.memos.isEmpty)
    }

    // MARK: Deleting

    func testDeletingAVoiceMemoRemovesItsAudio() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(20, f)
        f.session.stop()
        let memo = try savedMemo(f.session)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoAudioRecord>()), 1)

        let removed = f.store.deleteMemo(id: memo.id)

        XCTAssertEqual(removed, memo)
        XCTAssertTrue(f.store.memos.isEmpty)
        XCTAssertNil(f.store.memo(id: memo.id))
        XCTAssertNil(f.store.audioData(forMemoID: memo.id))
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 0)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoAudioRecord>()), 0)
    }

    func testDeletingAVoiceMemoLeavesOtherMemosAudioAlone() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(20, f)
        f.session.stop()
        let first = try savedMemo(f.session)
        f.recorder.recordedBytes = Data([7, 7, 7])
        await f.session.begin()
        recordSeconds(20, f)
        f.session.stop()
        let second = try savedMemo(f.session)

        _ = f.store.deleteMemo(id: first.id)

        XCTAssertEqual(f.store.audioData(forMemoID: second.id), Data([7, 7, 7]))
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoAudioRecord>()), 1)
    }

    // MARK: Launch purge and closing

    func testVoiceMemosSurviveTheLaunchPurgeThatDiscardsEmptyWrittenMemos() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(20, f)
        f.session.stop()
        let voice = try savedMemo(f.session)
        await f.store.transcriptionsSettled()
        let written = try XCTUnwrap(f.store.addWrittenMemo(text: "Soon empty"))
        _ = f.store.editMemo(id: written.id, text: "")

        let relaunched = MemoStore(modelContainer: f.container, now: { f.clock.now }, calendar: calendar)

        XCTAssertNil(relaunched.memo(id: written.id))
        let kept = try XCTUnwrap(relaunched.memo(id: voice.id))
        XCTAssertEqual(kept.kind, .voice)
        XCTAssertEqual(kept.text, "")
        XCTAssertEqual(relaunched.audioData(forMemoID: voice.id), f.recorder.recordedBytes)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoAudioRecord>()), 1)
    }

    func testClosingAVoiceMemoWithNoTranscriptKeepsIt() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(20, f)
        f.session.stop()
        let id = try savedMemo(f.session).id
        await f.store.transcriptionsSettled()

        XCTAssertNil(f.store.closeMemo(id: id))
        XCTAssertNotNil(f.store.memo(id: id))
    }

    func testVoiceMemosPersistAcrossReopening() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(33, f)
        f.session.stop()
        await f.store.transcriptionsSettled()
        let memo = try XCTUnwrap(f.store.memos.first)

        let reopened = MemoStore(modelContainer: f.container, now: { f.clock.now }, calendar: calendar)
        // A memo that couldn't be transcribed is tried again on launch.
        await reopened.transcriptionsSettled()

        XCTAssertEqual(reopened.memos, [memo])
        XCTAssertEqual(reopened.memos.first?.duration, 33)
        XCTAssertEqual(reopened.audioData(forMemoID: memo.id), f.recorder.recordedBytes)
    }

    // MARK: Transcription seam

    func testATranscriberFillsInTheTranscriptAndTheDetailLine() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .transcript("Buy milk\nand eggs")))
        await f.session.begin()
        recordSeconds(6, f)
        f.session.stop()
        let id = try savedMemo(f.session).id

        await f.store.transcriptionsSettled()

        let memo = try XCTUnwrap(f.store.memo(id: id))
        XCTAssertEqual(memo.transcriptState, .transcribed)
        XCTAssertEqual(memo.text, "Buy milk\nand eggs")
        XCTAssertEqual(memo.detail, "Buy milk and eggs")
        XCTAssertEqual(memo.title, "Voice memo")
        XCTAssertEqual(f.store.memos, [memo])
    }

    func testATranscriptThatIsBlankIsNoTranscript() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .transcript("  \n ")))
        await f.session.begin()
        recordSeconds(6, f)
        f.session.stop()
        let id = try savedMemo(f.session).id

        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
    }

    func testTryAgainTranscribesAMemoWithNoTranscriptAgain() async throws {
        let transcriber = ScriptedTranscriber()
        let f = try makeFixture(transcriber: transcriber)
        await f.session.begin()
        recordSeconds(6, f)
        f.session.stop()
        let id = try savedMemo(f.session).id
        transcriber.release(.noSpeech)
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: id)?.detail, "No transcript")

        let retried = try XCTUnwrap(f.store.retryTranscription(id: id))
        XCTAssertEqual(retried.transcriptState, .transcribing)
        XCTAssertEqual(retried.detail, "Transcribing…")
        transcriber.release(.transcript("Second time lucky"))
        await f.store.transcriptionsSettled()

        let memo = try XCTUnwrap(f.store.memo(id: id))
        XCTAssertEqual(memo.transcriptState, .transcribed)
        XCTAssertEqual(memo.text, "Second time lucky")
        XCTAssertEqual(transcriber.transcribedIDs, [id, id])
    }

    func testTryAgainWithTheNoOpTranscriberEndsAsNoTranscriptAgain() async throws {
        let f = try makeFixture()
        await f.session.begin()
        recordSeconds(6, f)
        f.session.stop()
        let id = try savedMemo(f.session).id
        await f.store.transcriptionsSettled()

        f.store.retryTranscription(id: id)
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
        XCTAssertEqual(f.store.audioData(forMemoID: id), f.recorder.recordedBytes)
    }

    func testTryAgainDoesNothingForATranscribedMemoOrAWrittenMemo() async throws {
        let transcriber = ScriptedTranscriber(immediate: .transcript("Done"))
        let f = try makeFixture(transcriber: transcriber)
        await f.session.begin()
        recordSeconds(6, f)
        f.session.stop()
        let id = try savedMemo(f.session).id
        await f.store.transcriptionsSettled()
        let written = try XCTUnwrap(f.store.addWrittenMemo(text: "Words"))

        let transcribed = f.store.retryTranscription(id: id)
        XCTAssertNil(f.store.retryTranscription(id: written.id))
        XCTAssertNil(f.store.retryTranscription(id: UUID()))
        await f.store.transcriptionsSettled()

        XCTAssertEqual(transcribed?.transcriptState, .transcribed)
        XCTAssertEqual(transcriber.transcribedIDs, [id])
    }

    func testTranscriptionsRunOneAtATime() async throws {
        let transcriber = ScriptedTranscriber()
        let f = try makeFixture(transcriber: transcriber)
        var ids: [UUID] = []
        for _ in 0..<3 {
            await f.session.begin()
            recordSeconds(5, f)
            f.session.stop()
            ids.append(try savedMemo(f.session).id)
        }

        for _ in 0..<3 { transcriber.release(.transcript("ok")) }
        await f.store.transcriptionsSettled()

        XCTAssertEqual(transcriber.peakConcurrency, 1)
        XCTAssertEqual(transcriber.transcribedIDs, ids)
        XCTAssertTrue(f.store.memos.allSatisfy { $0.transcriptState == .transcribed })
    }

    func testAMemoDeletedWhileTranscribingStaysDeleted() async throws {
        let transcriber = ScriptedTranscriber()
        let f = try makeFixture(transcriber: transcriber)
        await f.session.begin()
        recordSeconds(5, f)
        f.session.stop()
        let id = try savedMemo(f.session).id

        _ = f.store.deleteMemo(id: id)
        transcriber.release(.transcript("Too late"))
        await f.store.transcriptionsSettled()

        XCTAssertNil(f.store.memo(id: id))
        XCTAssertTrue(f.store.memos.isEmpty)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 0)
    }

    func testAMemoLeftTranscribingByAQuitIsTranscribedOnTheNextLaunch() async throws {
        let held = ScriptedTranscriber()
        let f = try makeFixture(transcriber: held)
        await f.session.begin()
        recordSeconds(5, f)
        f.session.stop()
        let id = try savedMemo(f.session).id
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .transcribing)

        let relaunchTranscriber = ScriptedTranscriber(immediate: .transcript("Picked up again"))
        let relaunched = MemoStore(
            modelContainer: f.container,
            now: { f.clock.now },
            calendar: calendar,
            transcriber: relaunchTranscriber
        )
        await relaunched.transcriptionsSettled()

        XCTAssertEqual(relaunched.memo(id: id)?.text, "Picked up again")
        XCTAssertEqual(relaunchTranscriber.transcribedIDs, [id])
        held.release(.noSpeech)
        await f.store.transcriptionsSettled()
    }

    func testEditingATranscriptSavesItWithoutTouchingTheAudio() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .transcript("Mistaken words")))
        await f.session.begin()
        recordSeconds(6, f)
        f.session.stop()
        let id = try savedMemo(f.session).id
        await f.store.transcriptionsSettled()

        let edited = try XCTUnwrap(f.store.editMemo(id: id, text: "Corrected words"))

        XCTAssertEqual(edited.text, "Corrected words")
        XCTAssertEqual(edited.transcriptState, .transcribed)
        XCTAssertEqual(edited.duration, 6)
        XCTAssertEqual(f.store.audioData(forMemoID: id), f.recorder.recordedBytes)
    }

    // MARK: Saving the same recording twice

    func testSavingTheSameRecordingTwiceKeepsOneMemo() throws {
        let f = try makeFixture()
        let audio = RecordedAudio(id: UUID(), startedAt: try moment(29, 9), duration: 4, data: Data([5]))

        let first = f.store.addVoiceMemo(audio, stoppedAtCap: false)
        let second = f.store.addVoiceMemo(audio, stoppedAtCap: false)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(f.store.memos.count, 1)
        XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<MemoAudioRecord>()), 1)
    }

    // MARK: Presentation

    func testDurationsReadAsMinutesAndSeconds() {
        XCTAssertEqual(Memo.formattedDuration(0), "0:00")
        XCTAssertEqual(Memo.formattedDuration(42.9), "0:42")
        XCTAssertEqual(Memo.formattedDuration(65), "1:05")
        XCTAssertEqual(Memo.formattedDuration(600), "10:00")
    }
}
