import SwiftData
import XCTest

/// Behavior of **Voice memo** titles: one on-device title generated when the **Transcript** is
/// first finalized, the user's rename winning over it, no regeneration, and the "Voice memo"
/// fallback. A fake language model stands in for Apple Intelligence, which doesn't run in the
/// Simulator; real titles are checked on an Apple Intelligence device.
@MainActor
final class VoiceMemoTitleBehaviorTests: XCTestCase {
    private struct Fixture {
        let model: FakeOnDeviceLanguageModel
        let transcriber: ScriptedTranscriber
        let container: ModelContainer
        let store: MemoStore
    }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private func makeFixture(
        availability: OnDeviceLanguageAvailability = .available,
        title: String = "Dentist and flights",
        transcriber: ScriptedTranscriber = ScriptedTranscriber()
    ) throws -> Fixture {
        let model = FakeOnDeviceLanguageModel(availability: availability)
        model.titleAnswer = .title(title)
        let container = try KyoModelContainer.make(inMemory: true)
        return Fixture(model: model, transcriber: transcriber, container: container, store: makeStore(container, model, transcriber))
    }

    private func makeStore(
        _ container: ModelContainer,
        _ model: FakeOnDeviceLanguageModel,
        _ transcriber: ScriptedTranscriber
    ) -> MemoStore {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 9, minute: 41)) ?? .now
        return MemoStore(
            modelContainer: container,
            now: { now },
            calendar: calendar,
            transcriber: transcriber,
            languageModel: model
        )
    }

    /// Saves a Voice memo, which starts out Transcribing.
    private func saveVoiceMemo(_ f: Fixture) -> UUID {
        let startedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 9, minute: 40)) ?? .now
        let audio = RecordedAudio(id: UUID(), startedAt: startedAt, duration: 6, data: Data([1, 2, 3]))
        return f.store.addVoiceMemo(audio, stoppedAtCap: false).id
    }

    private func finishTranscribing(_ f: Fixture, with transcript: String = "Call the dentist and book flights") async {
        f.transcriber.release(.transcript(transcript))
        await f.store.transcriptionsSettled()
    }

    /// Waits for work the store does on its own tasks.
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

    // MARK: Generation

    func testAVoiceMemoIsTitledOnceItsTranscriptIsFinalized() async throws {
        let f = try makeFixture()
        let id = saveVoiceMemo(f)
        XCTAssertEqual(f.store.memo(id: id)?.title, "Voice memo")
        XCTAssertTrue(f.model.receivedTitleTexts.isEmpty)

        await finishTranscribing(f)

        XCTAssertEqual(f.model.receivedTitleTexts, ["Call the dentist and book flights"])
        let memo = try XCTUnwrap(f.store.memo(id: id))
        XCTAssertEqual(memo.title, "Dentist and flights")
        XCTAssertFalse(memo.isTitleUserSet)
        XCTAssertEqual(f.store.memos.first?.title, "Dentist and flights")
    }

    func testTheTranscriptShowsBeforeItsTitleIsGenerated() async throws {
        let f = try makeFixture()
        f.model.holdsTitleRequest = true
        let id = saveVoiceMemo(f)
        f.transcriber.release(.transcript("Call the dentist"))
        await eventually("the title request") { !f.model.receivedTitleTexts.isEmpty }

        let memo = try XCTUnwrap(f.store.memo(id: id))
        XCTAssertEqual(memo.transcriptState, .transcribed)
        XCTAssertEqual(memo.title, "Voice memo")

        f.model.finishPendingTitleRequest()
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: id)?.title, "Dentist and flights")
    }

    func testAGeneratedTitleIsKeptAcrossARelaunchWithoutGeneratingAgain() async throws {
        let f = try makeFixture()
        let id = saveVoiceMemo(f)
        await finishTranscribing(f)

        let reopened = makeStore(f.container, f.model, f.transcriber)
        XCTAssertEqual(reopened.memo(id: id)?.title, "Dentist and flights")
        await reopened.transcriptionsSettled()
        XCTAssertEqual(f.model.receivedTitleTexts.count, 1)
    }

    func testAGeneratedTitleIsTidiedIntoOneShortLine() async throws {
        let f = try makeFixture(title: "  \"Dentist\nand flights.\"  ")
        let id = saveVoiceMemo(f)
        await finishTranscribing(f)
        XCTAssertEqual(f.store.memo(id: id)?.title, "Dentist and flights")
    }

    func testALongTranscriptTitlesFromTheBeginningThatFits() async throws {
        let f = try makeFixture()
        f.model.budget = 10
        let id = saveVoiceMemo(f)
        await finishTranscribing(f, with: "Call the dentist and book flights")

        XCTAssertEqual(f.model.receivedTitleTexts, ["Call the d"])
        XCTAssertEqual(f.store.memo(id: id)?.title, "Dentist and flights")
    }

    func testATranscriptThatArrivesFromAnAutomaticRetryIsTitledToo() async throws {
        let transcriber = ScriptedTranscriber(immediate: .modelNotReady)
        let f = try makeFixture(transcriber: transcriber)
        let id = saveVoiceMemo(f)
        await f.store.transcriptionsSettled()
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .noTranscript)
        XCTAssertEqual(f.store.memo(id: id)?.title, "Voice memo")
        XCTAssertTrue(f.model.receivedTitleTexts.isEmpty)

        transcriber.answer(with: .transcript("Now it works"))
        transcriber.becomeReady()
        await eventually("the automatic retry") { f.store.memo(id: id)?.transcriptState == .transcribed }
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.model.receivedTitleTexts, ["Now it works"])
        XCTAssertEqual(f.store.memo(id: id)?.title, "Dentist and flights")
    }

    func testAMemoWithNoTranscriptIsNotTitled() async throws {
        let f = try makeFixture()
        let id = saveVoiceMemo(f)
        f.transcriber.release(.noSpeech)
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.title, "Voice memo")
        XCTAssertTrue(f.model.receivedTitleTexts.isEmpty)
    }

    // MARK: Rename

    func testRenamingAVoiceMemoKeepsTheUsersTitle() async throws {
        let f = try makeFixture()
        let id = saveVoiceMemo(f)
        await finishTranscribing(f)

        let renamed = f.store.renameMemo(id: id, title: "  Dentist  ")
        XCTAssertEqual(renamed?.title, "Dentist")
        XCTAssertEqual(renamed?.isTitleUserSet, true)
        XCTAssertEqual(f.store.memos.first?.title, "Dentist")
        XCTAssertEqual(makeStore(f.container, f.model, f.transcriber).memo(id: id)?.title, "Dentist")
    }

    func testARenameWhileTranscribingIsNeverOverwrittenByTheGeneratedTitle() async throws {
        let f = try makeFixture()
        let id = saveVoiceMemo(f)
        XCTAssertEqual(f.store.memo(id: id)?.transcriptState, .transcribing)

        f.store.renameMemo(id: id, title: "My dentist note")
        await finishTranscribing(f)

        let memo = try XCTUnwrap(f.store.memo(id: id))
        XCTAssertEqual(memo.transcriptState, .transcribed)
        XCTAssertEqual(memo.title, "My dentist note")
        XCTAssertTrue(f.model.receivedTitleTexts.isEmpty)
    }

    func testARenameWhileTheTitleIsBeingGeneratedWins() async throws {
        let f = try makeFixture()
        f.model.holdsTitleRequest = true
        let id = saveVoiceMemo(f)
        f.transcriber.release(.transcript("Call the dentist"))
        await eventually("the title request") { !f.model.receivedTitleTexts.isEmpty }

        f.store.renameMemo(id: id, title: "Mine")
        f.model.finishPendingTitleRequest()
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.title, "Mine")
    }

    func testClearingATitleShowsTheFallbackAndTheUsersChoiceStillStands() async throws {
        let f = try makeFixture()
        let id = saveVoiceMemo(f)
        f.store.renameMemo(id: id, title: "   ")
        await finishTranscribing(f)

        XCTAssertEqual(f.store.memo(id: id)?.title, "Voice memo")
        XCTAssertTrue(f.model.receivedTitleTexts.isEmpty)
    }

    func testAWrittenMemoCantBeRenamed() throws {
        let f = try makeFixture()
        let memo = try XCTUnwrap(f.store.addWrittenMemo(text: "Buy milk\nand eggs"))
        XCTAssertNil(f.store.renameMemo(id: memo.id, title: "Groceries"))
        XCTAssertEqual(f.store.memo(id: memo.id)?.title, "Buy milk")
    }

    func testRenamingAnUnknownMemoDoesNothing() throws {
        let f = try makeFixture()
        XCTAssertNil(f.store.renameMemo(id: UUID(), title: "Nothing"))
    }

    // MARK: Never regenerated

    func testEditingTheTranscriptNeverRegeneratesTheTitle() async throws {
        let f = try makeFixture()
        let id = saveVoiceMemo(f)
        await finishTranscribing(f)

        f.model.titleAnswer = .title("A different title")
        f.store.editMemo(id: id, text: "Something else entirely")
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.title, "Dentist and flights")
        XCTAssertEqual(f.model.receivedTitleTexts.count, 1)
    }

    func testEditingAUserTitledTranscriptKeepsTheUsersTitle() async throws {
        let f = try makeFixture()
        let id = saveVoiceMemo(f)
        await finishTranscribing(f)
        f.store.renameMemo(id: id, title: "Mine")

        f.store.editMemo(id: id, text: "New words")
        await f.store.transcriptionsSettled()

        XCTAssertEqual(f.store.memo(id: id)?.title, "Mine")
        XCTAssertEqual(f.model.receivedTitleTexts.count, 1)
    }

    func testAFailedGenerationLeavesTheFallbackAndIsNotRetried() async throws {
        let f = try makeFixture()
        f.model.titleAnswer = .failure
        let id = saveVoiceMemo(f)
        await finishTranscribing(f)
        XCTAssertEqual(f.store.memo(id: id)?.title, "Voice memo")

        f.model.titleAnswer = .title("Too late")
        f.store.editMemo(id: id, text: "More words")
        let reopened = makeStore(f.container, f.model, f.transcriber)
        await reopened.transcriptionsSettled()

        XCTAssertEqual(reopened.memo(id: id)?.title, "Voice memo")
        XCTAssertEqual(f.model.receivedTitleTexts.count, 1)
    }

    // MARK: Without Apple Intelligence

    func testWithoutAppleIntelligenceTheFallbackStaysWithNoLaterRetry() async throws {
        let f = try makeFixture(availability: .unavailable(.appleIntelligenceNotEnabled))
        let id = saveVoiceMemo(f)
        await finishTranscribing(f)

        XCTAssertEqual(f.store.memo(id: id)?.title, "Voice memo")
        XCTAssertTrue(f.model.receivedTitleTexts.isEmpty)

        // Apple Intelligence turns on later and the transcript is edited: still no title.
        f.model.availability = .available
        f.store.editMemo(id: id, text: "Edited words")
        let reopened = makeStore(f.container, f.model, f.transcriber)
        await reopened.transcriptionsSettled()

        XCTAssertEqual(reopened.memo(id: id)?.title, "Voice memo")
        XCTAssertTrue(f.model.receivedTitleTexts.isEmpty)
    }

    func testAUserCanStillRenameWithoutAppleIntelligence() async throws {
        let f = try makeFixture(availability: .unavailable(.deviceNotEligible))
        let id = saveVoiceMemo(f)
        await finishTranscribing(f)
        f.store.renameMemo(id: id, title: "Dentist")
        XCTAssertEqual(f.store.memo(id: id)?.title, "Dentist")
    }
}
