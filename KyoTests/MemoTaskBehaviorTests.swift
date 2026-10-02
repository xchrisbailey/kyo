import SwiftData
import XCTest

/// Behavior of **Memo → Task**: the **Suggested tasks** a memo yields, editing and ticking them,
/// adding them to **Today**, and the manual path. A fake language model stands in for Apple
/// Intelligence, which doesn't run in the Simulator; real model output is checked on a device.
@MainActor
final class MemoTaskBehaviorTests: XCTestCase {
    private struct Fixture {
        let model: FakeOnDeviceLanguageModel
        let tasks: TaskListStore
        let memos: MemoStore
        let clock: Clock
    }

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private func makeFixture(
        availability: OnDeviceLanguageAvailability = .available,
        answer: FakeOnDeviceLanguageModel.Answer = .suggestions([])
    ) throws -> Fixture {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 9, minute: 41)))
        let clock = Clock(start)
        let container = try KyoModelContainer.make(inMemory: true)
        return Fixture(
            model: FakeOnDeviceLanguageModel(availability: availability, answer: answer),
            tasks: TaskListStore(modelContainer: container, now: { clock.now }, calendar: calendar),
            memos: MemoStore(modelContainer: container, now: { clock.now }, calendar: calendar),
            clock: clock
        )
    }

    private func open(_ f: Fixture, text: String = "Call the dentist and book flights") -> MemoTaskSuggestions {
        MemoTaskSuggestions(memoText: text, model: f.model, tasks: f.tasks)
    }

    private func yieldUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    // MARK: Suggested tasks

    func testShowsFindingWhileTheModelWorksThenTheSuggestionsAllTicked() async throws {
        let f = try makeFixture(answer: .suggestions(["Call the dentist", "Book flights"]))
        f.model.holdsRequest = true
        let sheet = open(f)
        XCTAssertEqual(sheet.phase, .finding)
        XCTAssertTrue(sheet.rows.isEmpty)

        let loading = Task { await sheet.load() }
        await yieldUntil { !f.model.receivedTexts.isEmpty }
        XCTAssertEqual(sheet.phase, .finding)

        f.model.finishPendingRequest()
        await loading.value

        XCTAssertEqual(sheet.phase, .suggestions)
        XCTAssertEqual(sheet.rows.map(\.text), ["Call the dentist", "Book flights"])
        XCTAssertTrue(sheet.rows.allSatisfy { $0.isTicked && !$0.isAdded })
        XCTAssertEqual(sheet.addableCount, 2)
        XCTAssertEqual(f.model.receivedTexts, ["Call the dentist and book flights"])
    }

    func testAtMostFiveSuggestionsWithoutBlanksOrRepeats() async throws {
        let f = try makeFixture(answer: .suggestions(
            ["  One ", "", "one", "Two", "Three", "   ", "Four", "Five", "Six", "Seven"]
        ))
        let sheet = open(f)
        await sheet.load()

        XCTAssertEqual(sheet.rows.map(\.text), ["One", "Two", "Three", "Four", "Five"])
    }

    func testEditingASuggestionChangesTheTaskThatIsAdded() async throws {
        let f = try makeFixture(answer: .suggestions(["Call the dentist", "Book flights"]))
        let sheet = open(f)
        await sheet.load()

        sheet.edit(rowID: sheet.rows[0].id, text: "Call Dr. Lee about the crown")
        sheet.addToToday()

        XCTAssertEqual(f.tasks.tasks.map(\.text), ["Call Dr. Lee about the crown", "Book flights"])
    }

    // MARK: Adding to Today

    func testAddToTodayCreatesOnlyTheTickedSuggestionsAsPlainTasks() async throws {
        let f = try makeFixture(answer: .suggestions(["A", "B", "C"]))
        let sheet = open(f)
        await sheet.load()
        sheet.toggle(rowID: sheet.rows[1].id)
        XCTAssertEqual(sheet.addableCount, 2)

        XCTAssertEqual(sheet.addToToday(), 2)

        XCTAssertEqual(f.tasks.tasks.map(\.text), ["A", "C"])
        XCTAssertTrue(f.tasks.tasks.allSatisfy { !$0.isComplete })
        XCTAssertEqual(sheet.rows.map(\.isAdded), [true, false, true])
    }

    func testAddedSuggestionsCantBeAddedAgainWhileTheSheetIsOpen() async throws {
        let f = try makeFixture(answer: .suggestions(["A", "B"]))
        let sheet = open(f)
        await sheet.load()
        sheet.addToToday()
        XCTAssertEqual(sheet.addableCount, 0)

        XCTAssertEqual(sheet.addToToday(), 0)
        // Ticking or editing an added row does nothing, so it can't come back.
        sheet.toggle(rowID: sheet.rows[0].id)
        sheet.edit(rowID: sheet.rows[0].id, text: "Changed")
        XCTAssertEqual(sheet.addToToday(), 0)

        XCTAssertEqual(f.tasks.tasks.map(\.text), ["A", "B"])
        XCTAssertEqual(sheet.rows.map(\.text), ["A", "B"])
        XCTAssertTrue(sheet.rows.allSatisfy { $0.isAdded && $0.isTicked })
    }

    func testAddingTheTickedOnesLeavesTheUntickedOnesToAddLater() async throws {
        let f = try makeFixture(answer: .suggestions(["A", "B"]))
        let sheet = open(f)
        await sheet.load()
        sheet.toggle(rowID: sheet.rows[1].id)
        sheet.addToToday()
        sheet.toggle(rowID: sheet.rows[1].id)
        XCTAssertEqual(sheet.addableCount, 1)

        sheet.addToToday()

        XCTAssertEqual(f.tasks.tasks.map(\.text), ["A", "B"])
    }

    func testReopeningMemoToTaskSuggestsFromScratchWithNoMemoryOfEarlierAdditions() async throws {
        let f = try makeFixture(answer: .suggestions(["A", "B"]))
        let first = open(f)
        await first.load()
        first.addToToday()

        let second = open(f)
        XCTAssertEqual(second.phase, .finding)
        await second.load()

        XCTAssertEqual(f.model.receivedTexts.count, 2)
        XCTAssertEqual(second.rows.map(\.text), ["A", "B"])
        XCTAssertTrue(second.rows.allSatisfy { $0.isTicked && !$0.isAdded })
        XCTAssertEqual(second.addableCount, 2)
    }

    func testTasksFromAnOlderMemoLandOnToday() async throws {
        let f = try makeFixture(answer: .suggestions(["Renew passport"]))
        let memo = try XCTUnwrap(f.memos.addWrittenMemo(text: "Passport expires soon"))
        f.clock.now = f.clock.now.addingTimeInterval(3 * 86_400)
        f.memos.refreshForCurrentDay()
        f.tasks.refreshForCurrentDay()
        XCTAssertTrue(f.memos.memos.isEmpty, "the memo is in memo history now")
        let older = try XCTUnwrap(f.memos.memo(id: memo.id))

        let sheet = open(f, text: older.taskSourceText(currentText: older.text))
        await sheet.load()
        sheet.addToToday()

        XCTAssertEqual(f.model.receivedTexts, ["Passport expires soon"])
        XCTAssertEqual(f.tasks.tasks.map(\.text), ["Renew passport"])
    }

    // MARK: The manual path

    func testUnavailableModelOpensTheManualSheetWithoutAskingTheModel() async throws {
        let reasons: [OnDeviceLanguageAvailability.Reason] = [
            .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unsupportedLanguage,
        ]
        for reason in reasons {
            let f = try makeFixture(availability: .unavailable(reason), answer: .suggestions(["Never shown"]))
            let sheet = open(f)

            XCTAssertEqual(sheet.phase, .noSuggestions, "\(reason)")
            XCTAssertEqual(sheet.rows.map(\.text), [""], "\(reason)")
            await sheet.load()
            XCTAssertEqual(sheet.phase, .noSuggestions, "\(reason)")
            XCTAssertTrue(f.model.receivedTexts.isEmpty, "\(reason)")
        }
    }

    func testAModelThatFindsNothingFallsBackToTheManualSheet() async throws {
        let f = try makeFixture(answer: .suggestions([]))
        let sheet = open(f)
        await sheet.load()

        XCTAssertEqual(sheet.phase, .noSuggestions)
        XCTAssertEqual(sheet.rows.map(\.text), [""])
        XCTAssertEqual(f.model.receivedTexts.count, 1)
    }

    func testOnlyBlankSuggestionsFallBackToTheManualSheet() async throws {
        let f = try makeFixture(answer: .suggestions(["", "  "]))
        let sheet = open(f)
        await sheet.load()

        XCTAssertEqual(sheet.phase, .noSuggestions)
    }

    func testAModelErrorFallsBackToTheManualSheet() async throws {
        let f = try makeFixture(answer: .failure)
        let sheet = open(f)
        await sheet.load()

        XCTAssertEqual(sheet.phase, .noSuggestions)
        XCTAssertEqual(sheet.rows.map(\.text), [""])
    }

    func testAMemoWithNoTextOpensTheManualSheetWithoutAskingTheModel() async throws {
        for text in ["", "  \n "] {
            let f = try makeFixture(answer: .suggestions(["Never shown"]))
            let sheet = open(f, text: text)

            XCTAssertEqual(sheet.phase, .noSuggestions)
            XCTAssertEqual(sheet.rows.map(\.text), [""])
            await sheet.load()
            XCTAssertTrue(f.model.receivedTexts.isEmpty)
        }
    }

    func testAVoiceMemoThatIsTranscribingOrHasNoTranscriptHasNoTextForTasks() throws {
        let day = TaskCompletionDay(era: 1, year: 2026, month: 9, day: 29)
        func voice(_ state: Memo.TranscriptState, text: String) -> Memo {
            Memo(id: UUID(), kind: .voice, createdAt: .now, day: day, text: text, transcriptState: state)
        }

        XCTAssertEqual(voice(.transcribing, text: "").taskSourceText(currentText: ""), "")
        XCTAssertEqual(voice(.noTranscript, text: "").taskSourceText(currentText: ""), "")
        XCTAssertEqual(voice(.transcribed, text: "Pick up milk").taskSourceText(currentText: "Pick up milk, eggs"), "Pick up milk, eggs")
        let written = Memo(id: UUID(), kind: .written, createdAt: .now, day: day, text: "Old text")
        XCTAssertEqual(written.taskSourceText(currentText: "Edited text"), "Edited text")
    }

    func testTheManualSheetAddsTypedTasksAndIgnoresBlankRows() async throws {
        let f = try makeFixture(availability: .unavailable(.deviceNotEligible))
        let sheet = open(f, text: "")
        XCTAssertEqual(sheet.addableCount, 0)

        sheet.edit(rowID: sheet.rows[0].id, text: "  Water the plants ")
        let second = try XCTUnwrap(sheet.addAnother())
        XCTAssertEqual(sheet.rows.count, 2)
        XCTAssertEqual(sheet.addableCount, 1)
        sheet.edit(rowID: second, text: "Email Sam")
        XCTAssertEqual(sheet.addAnother() != nil, true)
        XCTAssertEqual(sheet.addableCount, 2)

        XCTAssertEqual(sheet.addToToday(), 2)

        XCTAssertEqual(f.tasks.tasks.map(\.text), ["Water the plants", "Email Sam"])
        XCTAssertEqual(sheet.rows.map(\.isAdded), [true, true, false])
    }

    func testAddAnotherIsOnlyOnTheManualPath() async throws {
        let f = try makeFixture(answer: .suggestions(["A"]))
        let sheet = open(f)
        XCTAssertNil(sheet.addAnother(), "still finding")
        await sheet.load()

        XCTAssertNil(sheet.addAnother())
        XCTAssertEqual(sheet.rows.count, 1)
    }

    // MARK: Truncation

    func testAnOverLongTextIsCutFromTheStartToTheTokensThatFit() async throws {
        let f = try makeFixture(answer: .suggestions(["A"]))
        f.model.budget = 120
        let text = (0..<40).map { "word\($0)" }.joined(separator: " ")
        XCTAssertGreaterThan(text.count, 120)
        let sheet = open(f, text: text)
        await sheet.load()

        let received = try XCTUnwrap(f.model.receivedTexts.first)
        XCTAssertEqual(f.model.receivedTexts.count, 1)
        XCTAssertTrue(text.hasPrefix(received), "the start of the text is kept")
        XCTAssertLessThanOrEqual(received.count, 120)
        // The longest beginning that fits: one more character would be over.
        XCTAssertEqual(received, String(text.prefix(120)).trimmingCharacters(in: .whitespaces))
        XCTAssertEqual(sheet.phase, .suggestions)
    }

    func testATextThatFitsGoesToTheModelWhole() async throws {
        let f = try makeFixture(answer: .suggestions(["A"]))
        f.model.budget = 50
        let text = String(repeating: "x", count: 50)
        let sheet = open(f, text: "  \(text)\n")
        await sheet.load()

        XCTAssertEqual(f.model.receivedTexts, [text])
    }

    func testNoRoomInTheContextOpensTheManualSheetWithoutAskingTheModel() async throws {
        let f = try makeFixture(answer: .suggestions(["Never shown"]))
        f.model.budget = 0
        let sheet = open(f)
        await sheet.load()

        XCTAssertEqual(sheet.phase, .noSuggestions)
        XCTAssertTrue(f.model.receivedTexts.isEmpty)
    }

    func testClosingTheSheetWhileTheModelWorksLeavesItFinding() async throws {
        let f = try makeFixture(answer: .suggestions(["A"]))
        f.model.holdsRequest = true
        let sheet = open(f)
        let loading = Task { await sheet.load() }
        await yieldUntil { !f.model.receivedTexts.isEmpty }

        loading.cancel()
        f.model.finishPendingRequest()
        await loading.value

        XCTAssertEqual(sheet.phase, .finding)
        XCTAssertTrue(f.tasks.tasks.isEmpty)
    }
}
