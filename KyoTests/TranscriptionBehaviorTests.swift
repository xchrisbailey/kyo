import Combine
import SwiftData
import XCTest

/// Behavior of **Voice memo** transcription: the Recording, Transcribing, Transcribed and No
/// transcript flow, the failure and retry paths, silence, transcript edits, and the live
/// transcript in the recorder. A fake transcriber and a fake live transcriber stand in for the
/// Speech framework, which doesn't run in the Simulator.
@MainActor
final class TranscriptionBehaviorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    /// The device language, which a test changes by hand.
    private final class DeviceLocale {
        var identifier = "en_US"
    }

    private struct Fixture {
        let locale: DeviceLocale
        let container: ModelContainer
        let clock: Clock
        let recorder: FakeAudioRecorder
        let live: FakeLiveTranscriber
        let store: MemoStore
        let session: VoiceRecordingSession
    }

    private func makeFixture(transcriber: any VoiceTranscriber = NoTranscriber()) throws -> Fixture {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 9, minute: 41)))
        let clock = Clock(start)
        let container = try KyoModelContainer.make(inMemory: true)
        let recorder = FakeAudioRecorder()
        let live = FakeLiveTranscriber()
        let locale = DeviceLocale()
        let store = MemoStore(
            modelContainer: container,
            now: { clock.now },
            calendar: calendar,
            transcriber: transcriber,
            deviceLocale: { locale.identifier }
        )
        let session = VoiceRecordingSession(recorder: recorder, memos: store, live: live, now: { clock.now })
        return Fixture(
            locale: locale, container: container, clock: clock, recorder: recorder, live: live, store: store, session: session
        )
    }

    /// Records for `seconds`, stops, and returns the saved memo's id.
    @discardableResult
    private func recordMemo(_ f: Fixture, seconds: TimeInterval = 6) async throws -> UUID {
        await f.session.begin()
        f.clock.advance(seconds)
        f.session.tick()
        f.session.stop()
        guard case .saved(let memo, _)? = f.session.outcome else {
            XCTFail("Expected a saved voice memo, got \(String(describing: f.session.outcome))")
            throw XCTSkip("no saved memo")
        }
        return memo.id
    }

    /// Waits for work the store or session does on its own tasks.
    private func eventually(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }

    private func reopenedStore(_ f: Fixture, transcriber: any VoiceTranscriber) -> MemoStore {
        MemoStore(
            modelContainer: f.container,
            now: { f.clock.now },
            calendar: calendar,
            transcriber: transcriber,
            deviceLocale: { f.locale.identifier }
        )
    }

    // MARK: State flow

    func testAVoiceMemoGoesFromRecordingToTranscribingToTranscribed() async throws {
        let transcriber = ScriptedTranscriber()
        let f = try makeFixture(transcriber: transcriber)
        await f.session.begin()
        XCTAssertEqual(f.session.phase, .recording)
        XCTAssertTrue(f.store.memos.isEmpty)

        f.clock.advance(6)
        f.session.tick()
        f.session.stop()
        guard case .saved(let saved, _)? = f.session.outcome else { return XCTFail("Expected a saved memo") }
        XCTAssertEqual(saved.transcriptState, .transcribing)
        XCTAssertEqual(saved.title, "Voice memo")
        XCTAssertEqual(saved.detail, "Transcribing…")

        transcriber.release(.transcript("Call the dentist"))
        await f.store.transcriptionsSettled()

        let memo = try XCTUnwrap(f.store.memo(id: saved.id))
        XCTAssertEqual(memo.transcriptState, .transcribed)
        XCTAssertEqual(memo.text, "Call the dentist")
        XCTAssertEqual(memo.title, "Voice memo")
    }

    func testTheTranscriptComesFromTheSavedAudioNotFromWhatWasHeardLive() async throws {
        let transcriber = ScriptedTranscriber()
        let f = try makeFixture(transcriber: transcriber)
        await f.session.begin()
        await eventually("live transcription to start") { f.session.liveStatus == .listening }
        f.live.hear("buy mill")

        f.clock.advance(4)
        f.session.tick()
        f.session.stop()
        guard case .saved(let saved, _)? = f.session.outcome else { return XCTFail("Expected a saved memo") }
        XCTAssertEqual(saved.text, "")

        transcriber.release(.transcript("Buy milk"))
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: saved.id)?.text, "Buy milk")
    }

    // MARK: Model not installed

    func testAMemoWhoseModelIsNotInstalledIsNoTranscriptAndKeepsItsAudio() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .modelNotReady))
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        let memo = try XCTUnwrap(f.store.memo(id: id))
        XCTAssertEqual(memo.transcriptState, .noTranscript)
        XCTAssertEqual(memo.detail, "No transcript")
        XCTAssertEqual(f.store.audioData(forMemoID: id), f.recorder.recordedBytes)
    }

    func testAMemoRetriesByItselfWhenTheModelFinishesInstalling() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        transcriber.answer(with: .transcript("Now it works"))
        transcriber.becomeReady()
        await eventually("the automatic retry") { f.store.memo(id: id)?.transcriptState == .transcribed }

        XCTAssertEqual(f.store.memo(id: id)?.text, "Now it works")
        XCTAssertEqual(transcriber.transcribedIDs, [id, id])
    }

    func testAnAutomaticRetryKeepsShowingNoTranscriptUntilItProducesATranscript() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        transcriber.answer(with: nil)

        transcriber.becomeReady()
        await eventually("the retry to start") { transcriber.transcribedIDs.count == 2 }

        // The retry is running, and nothing on screen says so.
        let memo = try XCTUnwrap(f.store.memo(id: id))
        XCTAssertEqual(memo.transcriptState, .noTranscript)
        XCTAssertEqual(memo.detail, "No transcript")
        XCTAssertEqual(f.store.memos, [memo])

        transcriber.release(.transcript("Worth the wait"))
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .transcribed)
        XCTAssertEqual(f.store.memo(id: id)?.text, "Worth the wait")
    }

    func testAnAutomaticRetryThatFailsAgainChangesNothingVisible() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        let before = try XCTUnwrap(f.store.memo(id: id))
        var changes = 0
        let subscription = f.store.$memos.dropFirst().sink { _ in changes += 1 }
        defer { subscription.cancel() }

        transcriber.becomeReady()
        await eventually("the retry to run") { transcriber.transcribedIDs.count == 2 }
        await f.store.transcriptionsSettled()

        XCTAssertEqual(changes, 0)
        XCTAssertEqual(f.store.memo(id: id), before)
    }

    func testAMemoStillWaitingForTheModelRetriesOnlyWhenThereIsASignal() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        transcriber.becomeReady()
        await eventually("the first retry") { transcriber.transcribedIDs.count == 2 }
        await f.store.transcriptionsSettled()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(transcriber.transcribedIDs.count, 2)

        transcriber.answer(with: .transcript("Third time"))
        transcriber.becomeReady()
        await eventually("the second retry") { f.store.memo(id: id)?.transcriptState == .transcribed }
    }

    func testAMemoWaitingForTheModelRetriesWhenKyoComesToTheFront() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        transcriber.answer(with: .transcript("Installed while away"))
        f.store.retryTranscriptionsWaitingForModel()
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.text, "Installed while away")
    }

    func testAMemoWaitingForTheModelRetriesOnTheNextLaunch() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .modelNotReady))
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        let relaunch = ScriptedTranscriber(immediate: .transcript("After relaunch"))
        let relaunched = reopenedStore(f, transcriber: relaunch)
        XCTAssertEqual(relaunched.memo(id: id)?.transcriptState, .noTranscript)
        await relaunched.transcriptionsSettled()

        XCTAssertEqual(relaunched.memo(id: id)?.text, "After relaunch")
        XCTAssertEqual(relaunch.transcribedIDs, [id])
    }

    func testAutomaticRetriesRunOneMemoAtATime() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        var ids: [UUID] = []
        for _ in 0..<3 { ids.append(try await recordMemo(f)) }
        await f.store.transcriptionsSettled()

        transcriber.answer(with: .transcript("ok"))
        transcriber.becomeReady()
        await eventually("every memo to be transcribed") {
            f.store.memos.allSatisfy { $0.transcriptState == .transcribed }
        }

        XCTAssertEqual(transcriber.peakConcurrency, 1)
        XCTAssertEqual(Set(transcriber.transcribedIDs.suffix(3)), Set(ids))
    }

    func testTwoSignalsInARowDoNotTranscribeTheSameMemoTwice() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        transcriber.answer(with: nil)

        f.store.retryTranscriptionsWaitingForModel()
        f.store.retryTranscriptionsWaitingForModel()
        await eventually("the retry to start") { transcriber.transcribedIDs.count == 2 }
        f.store.retryTranscriptionsWaitingForModel()
        transcriber.release(.transcript("Once"))
        await f.store.transcriptionsSettled()

        XCTAssertEqual(transcriber.transcribedIDs, [id, id])
        XCTAssertEqual(f.store.memo(id: id)?.text, "Once")
    }

    func testAutomaticRetryLeavesTranscribedAndWrittenMemosAlone() async throws {
        let transcriber = ScriptedTranscriber(immediate: .transcript("Done"))
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        let written = try XCTUnwrap(f.store.addWrittenMemo(text: "Words"))
        _ = f.store.editMemo(id: id, text: "Edited transcript")

        transcriber.becomeReady()
        f.store.retryTranscriptionsWaitingForModel()
        f.store.retryTranscriptionsAfterLocaleChange()
        await f.store.transcriptionsSettled()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(transcriber.transcribedIDs, [id])
        XCTAssertEqual(f.store.memo(id: id)?.text, "Edited transcript")
        XCTAssertEqual(f.store.memo(id: written.id)?.text, "Words")
    }

    func testAMemoDeletedWhileWaitingForTheModelIsNotRetried() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        _ = f.store.deleteMemo(id: id)
        transcriber.becomeReady()
        f.store.retryTranscriptionsWaitingForModel()
        await f.store.transcriptionsSettled()

        XCTAssertEqual(transcriber.transcribedIDs, [id])
        XCTAssertTrue(f.store.memos.isEmpty)
    }

    // MARK: Unsupported device or language

    func testAnUnsupportedMemoIsNoTranscriptAndNeverRetriesOnAnyOtherSignal() async throws {
        let transcriber = ScriptedTranscriber(immediate: .unsupported)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
        XCTAssertEqual(f.store.memo(id: id)?.detail, "No transcript")

        transcriber.becomeReady()
        f.store.retryTranscriptionsWaitingForModel()
        f.store.retryTranscriptionsAfterLocaleChange()
        await f.store.transcriptionsSettled()
        try await Task.sleep(for: .milliseconds(100))
        let relaunched = reopenedStore(f, transcriber: transcriber)
        await relaunched.transcriptionsSettled()

        XCTAssertEqual(transcriber.transcribedIDs, [id])
        XCTAssertEqual(relaunched.memo(id: id)?.transcriptState, .noTranscript)
    }

    func testChangingTheDeviceLanguageRetriesAnUnsupportedMemoWithoutShowingTranscribing() async throws {
        let transcriber = ScriptedTranscriber(immediate: .unsupported)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        transcriber.answer(with: nil)

        f.locale.identifier = "fr_FR"
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        await eventually("the retry to start") { transcriber.transcribedIDs.count == 2 }
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)

        transcriber.release(.transcript("Bonjour"))
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: id)?.text, "Bonjour")
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .transcribed)
    }

    func testALocaleChangeThatDoesNotChangeTheLanguageRetriesNothing() async throws {
        let transcriber = ScriptedTranscriber(immediate: .unsupported)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(transcriber.transcribedIDs, [id])
    }

    func testAnUnsupportedMemoRetriesAtLaunchWhenTheLanguageChangedWhileKyoWasClosed() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .unsupported))
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        let relaunch = ScriptedTranscriber(immediate: .transcript("Hola"))
        f.locale.identifier = "es_ES"
        let relaunched = reopenedStore(f, transcriber: relaunch)
        await relaunched.transcriptionsSettled()

        XCTAssertEqual(relaunched.memo(id: id)?.text, "Hola")
        XCTAssertEqual(relaunch.transcribedIDs, [id])
    }

    func testAnUnsupportedMemoRemembersTheNewLanguageAfterRetryingInIt() async throws {
        let transcriber = ScriptedTranscriber(immediate: .unsupported)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        f.locale.identifier = "fr_FR"
        f.store.retryTranscriptionsAfterLocaleChange()
        await f.store.transcriptionsSettled()
        XCTAssertEqual(transcriber.transcribedIDs, [id, id])

        // Still unsupported in French, so only another change of language tries again.
        f.store.retryTranscriptionsAfterLocaleChange()
        await f.store.transcriptionsSettled()
        XCTAssertEqual(transcriber.transcribedIDs, [id, id])
        f.locale.identifier = "de_DE"
        f.store.retryTranscriptionsAfterLocaleChange()
        await f.store.transcriptionsSettled()
        XCTAssertEqual(transcriber.transcribedIDs, [id, id, id])
    }

    // MARK: Analysis error

    func testAnAnalysisErrorRetriesOnceAtTheNextLaunchAndNotBefore() async throws {
        let transcriber = ScriptedTranscriber(immediate: .failed)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)

        transcriber.becomeReady()
        f.store.retryTranscriptionsWaitingForModel()
        f.store.retryTranscriptionsAfterLocaleChange()
        await f.store.transcriptionsSettled()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(transcriber.transcribedIDs, [id])

        let relaunch = ScriptedTranscriber(immediate: .transcript("Second try"))
        let relaunched = reopenedStore(f, transcriber: relaunch)
        XCTAssertEqual(relaunched.memo(id: id)?.transcriptState, .noTranscript)
        await relaunched.transcriptionsSettled()
        XCTAssertEqual(relaunched.memo(id: id)?.text, "Second try")
    }

    func testAnAnalysisErrorThatRepeatsOnTheLaunchRetryIsNotRetriedAgain() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .failed))
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        let secondLaunch = ScriptedTranscriber(immediate: .failed)
        let second = reopenedStore(f, transcriber: secondLaunch)
        await second.transcriptionsSettled()
        XCTAssertEqual(secondLaunch.transcribedIDs, [id])
        XCTAssertEqual(second.memo(id: id)?.transcriptState, .noTranscript)

        let thirdLaunch = ScriptedTranscriber(immediate: .failed)
        let third = reopenedStore(f, transcriber: thirdLaunch)
        await third.transcriptionsSettled()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(thirdLaunch.transcribedIDs, [])
        XCTAssertEqual(third.memo(id: id)?.transcriptState, .noTranscript)
    }

    func testTheLaunchRetryAfterAnErrorShowsNothingUntilItSucceeds() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .failed))
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        let relaunch = ScriptedTranscriber()
        let relaunched = reopenedStore(f, transcriber: relaunch)
        await eventually("the retry to start") { relaunch.transcribedIDs.count == 1 }

        XCTAssertEqual(relaunched.memo(id: id)?.transcriptState, .noTranscript)
        relaunch.release(.transcript("Eventually"))
        await relaunched.transcriptionsSettled()
        XCTAssertEqual(relaunched.memo(id: id)?.transcriptState, .transcribed)
    }

    // MARK: Try again

    func testTryAgainWorksForEveryCauseAndShowsTranscribingAtOnce() async throws {
        for outcome in [TranscriptionOutcome.modelNotReady, .unsupported, .failed, .noSpeech] {
            let transcriber = ScriptedTranscriber(immediate: outcome)
            let f = try makeFixture(transcriber: transcriber)
            let id = try await recordMemo(f)
            await f.store.transcriptionsSettled()
            XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript, "\(outcome)")

            transcriber.answer(with: nil)
            let retried = try XCTUnwrap(f.store.retryTranscription(id: id))
            XCTAssertEqual(retried.transcriptState, .transcribing, "\(outcome)")
            XCTAssertEqual(retried.detail, "Transcribing…", "\(outcome)")
            transcriber.release(.transcript("Second time lucky"))
            await f.store.transcriptionsSettled()

            XCTAssertEqual(f.store.memo(id: id)?.text, "Second time lucky", "\(outcome)")
            XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .transcribed, "\(outcome)")
        }
    }

    func testTryAgainThatFailsAgainKeepsTheAudioAndStaysNoTranscript() async throws {
        let transcriber = ScriptedTranscriber(immediate: .failed)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        f.store.retryTranscription(id: id)
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
        XCTAssertEqual(f.store.audioData(forMemoID: id), f.recorder.recordedBytes)
        XCTAssertEqual(transcriber.transcribedIDs, [id, id])
    }

    func testTryAgainDuringAnAutomaticRetryShowsTranscribingAndWins() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        transcriber.answer(with: nil)

        transcriber.becomeReady()
        await eventually("the automatic retry to start") { transcriber.transcribedIDs.count == 2 }
        f.store.retryTranscription(id: id)
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .transcribing)

        // The overtaken retry ends first and changes nothing; the visible one settles the memo.
        transcriber.release(.noSpeech)
        await eventually("the second transcription to start") { transcriber.transcribedIDs.count == 3 }
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .transcribing)
        transcriber.release(.transcript("Tried again"))
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.text, "Tried again")
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .transcribed)
    }

    // MARK: Silence

    func testSilenceIsNoTranscriptAndIsNotRetriedAutomatically() async throws {
        let transcriber = ScriptedTranscriber(immediate: .noSpeech)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
        XCTAssertEqual(f.store.memo(id: id)?.detail, "No transcript")

        transcriber.becomeReady()
        f.store.retryTranscriptionsWaitingForModel()
        f.store.retryTranscriptionsAfterLocaleChange()
        await f.store.transcriptionsSettled()
        try await Task.sleep(for: .milliseconds(100))
        let relaunched = reopenedStore(f, transcriber: transcriber)
        await relaunched.transcriptionsSettled()

        XCTAssertEqual(transcriber.transcribedIDs, [id])
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
    }

    func testATranscriptOfOnlyWhitespaceCountsAsSilence() async throws {
        let transcriber = ScriptedTranscriber(immediate: .transcript("  \n "))
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        transcriber.becomeReady()
        f.store.retryTranscriptionsWaitingForModel()
        await f.store.transcriptionsSettled()
        let relaunched = reopenedStore(f, transcriber: transcriber)
        await relaunched.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
        XCTAssertEqual(transcriber.transcribedIDs, [id])
    }

    func testAMemoThatTurnsOutSilentOnAnAutomaticRetryStopsRetrying() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        transcriber.answer(with: .noSpeech)
        f.store.retryTranscriptionsWaitingForModel()
        await f.store.transcriptionsSettled()
        f.store.retryTranscriptionsWaitingForModel()
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
        XCTAssertEqual(transcriber.transcribedIDs, [id, id])
    }

    // MARK: Editing

    func testEditingATranscriptNeverChangesTheAudioOrTheState() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .transcript("Mistaken words")))
        let id = try await recordMemo(f, seconds: 9)
        await f.store.transcriptionsSettled()

        let edited = try XCTUnwrap(f.store.editMemo(id: id, text: "Corrected words"))
        XCTAssertEqual(edited.text, "Corrected words")
        XCTAssertEqual(edited.transcriptState, .transcribed)
        XCTAssertEqual(edited.duration, 9)
        XCTAssertEqual(f.store.audioData(forMemoID: id), f.recorder.recordedBytes)

        let reopened = reopenedStore(f, transcriber: NoTranscriber())
        XCTAssertEqual(reopened.memo(id: id)?.text, "Corrected words")
        XCTAssertEqual(reopened.audioData(forMemoID: id), f.recorder.recordedBytes)
    }

    func testEmptyingATranscriptKeepsTheVoiceMemoAndItsAudio() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .transcript("Some words")))
        let id = try await recordMemo(f)
        await f.store.transcriptionsSettled()

        _ = f.store.editMemo(id: id, text: "")
        f.store.closeMemo(id: id)

        XCTAssertNotNil(f.store.memo(id: id))
        XCTAssertEqual(f.store.audioData(forMemoID: id), f.recorder.recordedBytes)
    }

    // MARK: Live transcript in the recorder

    func testLiveTranscriptionStartsWithRecordingAndShowsWhatItHears() async throws {
        let f = try makeFixture()
        XCTAssertEqual(f.session.liveTranscript, "")

        await f.session.begin()
        await eventually("live transcription to start") { f.session.liveStatus == .listening }
        XCTAssertEqual(f.live.startCount, 1)

        f.live.hear("Pick up")
        XCTAssertEqual(f.session.liveTranscript, "Pick up")
        f.live.hear("Pick up the dry cleaning")
        XCTAssertEqual(f.session.liveTranscript, "Pick up the dry cleaning")
    }

    func testWhenLiveTranscriptionIsUnavailableRecordingWorksAndTheRecorderSaysSo() async throws {
        let f = try makeFixture(transcriber: ScriptedTranscriber(immediate: .transcript("Heard it afterwards")))
        f.live.isAvailable = false

        await f.session.begin()
        await eventually("live transcription to give up") { f.session.liveStatus == .unavailable }
        XCTAssertEqual(f.session.phase, .recording)
        XCTAssertEqual(f.session.liveTranscript, "")

        f.clock.advance(5)
        f.session.tick()
        f.session.stop()
        guard case .saved(let memo, _)? = f.session.outcome else { return XCTFail("Expected a saved memo") }
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: memo.id)?.text, "Heard it afterwards")
        XCTAssertEqual(f.store.audioData(forMemoID: memo.id), f.recorder.recordedBytes)
    }

    func testStoppingAndDiscardingStopListening() async throws {
        let f = try makeFixture()
        await f.session.begin()
        await eventually("live transcription to start") { f.session.liveStatus == .listening }
        f.session.stop()
        XCTAssertEqual(f.live.stopCount, 1)

        await f.session.begin()
        await eventually("live transcription to start again") { f.live.startCount == 2 }
        f.session.discard()
        XCTAssertEqual(f.live.stopCount, 2)
        XCTAssertEqual(f.session.phase, .idle)
    }

    func testAPauseKeepsTheLiveTranscriptAndResumingCarriesOnAfterIt() async throws {
        let f = try makeFixture()
        await f.session.begin()
        await eventually("live transcription to start") { f.session.liveStatus == .listening }
        f.live.hear("First part")

        f.recorder.simulateInterruption()
        XCTAssertEqual(f.session.phase, .paused)
        XCTAssertEqual(f.live.stopCount, 1)
        XCTAssertEqual(f.session.liveTranscript, "First part")

        await f.session.resume()
        await eventually("listening to resume") { f.live.startCount == 2 && f.session.liveStatus == .listening }
        f.live.hear("second part")
        XCTAssertEqual(f.session.liveTranscript, "First part second part")
    }

    func testResumingDoesNotRetryLiveTranscriptionThatNeverStarted() async throws {
        let f = try makeFixture()
        f.live.isAvailable = false
        await f.session.begin()
        await eventually("live transcription to give up") { f.session.liveStatus == .unavailable }

        f.recorder.simulateInterruption()
        await f.session.resume()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(f.live.startCount, 1)
        XCTAssertEqual(f.session.liveStatus, .unavailable)
    }

    func testStoppingWhileLiveTranscriptionIsStartingLeavesItOff() async throws {
        let f = try makeFixture()
        f.live.holdsStart = true
        await f.session.begin()
        XCTAssertEqual(f.session.liveStatus, .starting)

        f.session.stop()
        f.live.finishPendingStart()
        try await Task.sleep(for: .milliseconds(50))

        f.live.hear("too late")
        XCTAssertEqual(f.session.liveTranscript, "")
        XCTAssertEqual(f.session.liveStatus, .starting)
    }

    func testANewRecordingStartsWithAnEmptyLiveTranscript() async throws {
        let f = try makeFixture()
        await f.session.begin()
        await eventually("live transcription to start") { f.session.liveStatus == .listening }
        f.live.hear("Old words")
        f.session.stop()

        await f.session.begin()
        XCTAssertEqual(f.session.liveTranscript, "")
        await eventually("live transcription to start again") { f.live.startCount == 2 }
        f.live.hear("New words")
        XCTAssertEqual(f.session.liveTranscript, "New words")
    }
}
