import SwiftData
import XCTest

/// Behavior of the Memos sheet through `MemoStoreBehavior`: **See all** visibility, memos grouped
/// by day (Today, then **Memo history**), search over titles, text and transcripts, snippets with
/// highlights, and the no-results state. Runs on an in-memory store with a controllable clock.
@MainActor
final class MemoHistoryBehaviorTests: XCTestCase {
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private struct Fixture {
        let clock: Clock
        let container: ModelContainer
        let store: MemoStore
        let model: FakeOnDeviceLanguageModel
    }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    /// Today is Tuesday, September 29, 2026.
    private func makeFixture(transcript: String = "Call the dentist and book flights") throws -> Fixture {
        let clock = Clock(try date(2026, 9, 29, 18))
        let container = try KyoModelContainer.make(inMemory: true)
        let model = FakeOnDeviceLanguageModel(availability: .available)
        model.titleAnswer = .title("Dentist and flights")
        let store = MemoStore(
            modelContainer: container,
            now: { clock.now },
            calendar: calendar,
            transcriber: ScriptedTranscriber(immediate: .transcript(transcript)),
            languageModel: model
        )
        return Fixture(clock: clock, container: container, store: store, model: model)
    }

    /// Writes a Written memo as of the given moment, then puts the clock back.
    @discardableResult
    private func write(_ f: Fixture, _ text: String, on moment: Date) throws -> Memo {
        let restored = f.clock.now
        f.clock.now = moment
        let memo = try XCTUnwrap(f.store.addWrittenMemo(text: text))
        f.clock.now = restored
        f.store.refreshForCurrentDay()
        return memo
    }

    /// Records a Voice memo as of the given moment and waits for its Transcript and title.
    @discardableResult
    private func record(_ f: Fixture, on moment: Date) async throws -> Memo {
        let audio = RecordedAudio(id: UUID(), startedAt: moment, duration: 6, data: Data([1, 2, 3]))
        let memo = f.store.addVoiceMemo(audio, stoppedAtCap: false)
        await f.store.transcriptionsSettled()
        return try XCTUnwrap(f.store.memo(id: memo.id))
    }

    private func titles(_ page: MemoGroupsPage) -> [[String]] {
        page.groups.map { $0.results.map(\.memo.title) }
    }

    private func search(_ f: Fixture, _ query: String) -> MemoGroupsPage {
        f.store.memoGroups(matching: query, limit: 100)
    }

    // MARK: See all

    func testSeeAllShowsOnlyWhileAnyMemoExistsEvenWhenTodayHasNone() throws {
        let f = try makeFixture()
        XCTAssertFalse(f.store.hasMemos)

        let old = try write(f, "Last week", on: try date(2026, 9, 22))

        XCTAssertTrue(f.store.memos.isEmpty)
        XCTAssertTrue(f.store.hasMemos)

        f.store.deleteMemo(id: old.id)
        XCTAssertFalse(f.store.hasMemos)
    }

    // MARK: Grouping

    func testMemosAreGroupedByDayNewestFirstWithTodayAtTheTop() throws {
        let f = try makeFixture()
        try write(f, "Earlier this year", on: try date(2026, 3, 3))
        try write(f, "Yesterday morning", on: try date(2026, 9, 28, 8))
        try write(f, "Yesterday evening", on: try date(2026, 9, 28, 20))
        try write(f, "Today", on: try date(2026, 9, 29, 7))
        try write(f, "Last week", on: try date(2026, 9, 22))

        let page = search(f, "")

        XCTAssertEqual(page.groups.map(\.title), ["Today", "Yesterday", "Tue, Sep 22", "Tue, Mar 3"])
        XCTAssertEqual(titles(page), [["Today"], ["Yesterday evening", "Yesterday morning"], ["Last week"], ["Earlier this year"]])
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.noResultsMessage)
    }

    func testDaysFromAnEarlierYearShowTheYear() throws {
        let f = try makeFixture()
        try write(f, "Last December", on: try date(2025, 12, 2))

        let header = try XCTUnwrap(search(f, "").groups.first?.title)

        XCTAssertEqual(header, "Tue, Dec 2, 2025")
    }

    func testThereIsNoTodayGroupWhenTodayHasNoMemos() throws {
        let f = try makeFixture()
        try write(f, "Yesterday", on: try date(2026, 9, 28))

        XCTAssertEqual(search(f, "").groups.map(\.title), ["Yesterday"])
    }

    func testAnEmptyStoreHasNoGroupsAndNoNoResultsMessage() throws {
        let f = try makeFixture()

        let page = search(f, "")

        XCTAssertTrue(page.groups.isEmpty)
        XCTAssertNil(page.noResultsMessage)
    }

    func testTheListLoadsOnePageAtATimeOldestLast() throws {
        let f = try makeFixture()
        for day in 1...5 {
            try write(f, "Memo \(day)", on: try date(2026, 9, day))
        }

        let first = f.store.memoGroups(matching: "", limit: 2)
        XCTAssertEqual(titles(first), [["Memo 5"], ["Memo 4"]])
        XCTAssertTrue(first.hasMore)

        let all = f.store.memoGroups(matching: "", limit: 5)
        XCTAssertEqual(titles(all).flatMap { $0 }, ["Memo 5", "Memo 4", "Memo 3", "Memo 2", "Memo 1"])
        XCTAssertFalse(all.hasMore)
    }

    func testAMemoStaysOnItsOwnDayWhenEditedOrRenamedLater() async throws {
        let f = try makeFixture()
        let written = try write(f, "Old idea", on: try date(2026, 9, 20))
        let voice = try await record(f, on: try date(2026, 9, 21))

        f.store.editMemo(id: written.id, text: "Old idea, revised")
        f.store.renameMemo(id: voice.id, title: "Renamed")

        let page = search(f, "")
        XCTAssertEqual(page.groups.map(\.title), ["Mon, Sep 21", "Sun, Sep 20"])
        XCTAssertEqual(titles(page), [["Renamed"], ["Old idea, revised"]])
    }

    func testDeletingAPastMemoRemovesItFromTheGroups() throws {
        let f = try makeFixture()
        let old = try write(f, "Old", on: try date(2026, 9, 20))
        try write(f, "Kept", on: try date(2026, 9, 21))

        f.store.deleteMemo(id: old.id)

        XCTAssertEqual(titles(search(f, "")), [["Kept"]])
    }

    // MARK: Search

    func testSearchIgnoresCase() throws {
        let f = try makeFixture()
        try write(f, "Weekend Trail Plan", on: try date(2026, 9, 28))

        XCTAssertEqual(titles(search(f, "trail PLAN")), [["Weekend Trail Plan"]])
    }

    func testSearchIgnoresAccentsInBothDirections() throws {
        let f = try makeFixture()
        try write(f, "Meet at the café", on: try date(2026, 9, 28))
        try write(f, "Resume draft", on: try date(2026, 9, 27))

        XCTAssertEqual(titles(search(f, "cafe")), [["Meet at the café"]])
        XCTAssertEqual(titles(search(f, "CAFÉ")), [["Meet at the café"]])
        XCTAssertEqual(titles(search(f, "résumé")), [["Resume draft"]])
    }

    func testSearchMatchesPartOfAWord() throws {
        let f = try makeFixture()
        try write(f, "Trail by the lake", on: try date(2026, 9, 28))

        XCTAssertEqual(titles(search(f, "ake")), [["Trail by the lake"]])
        XCTAssertEqual(titles(search(f, "tra")), [["Trail by the lake"]])
    }

    func testSearchMatchesWrittenTextBeyondTheTitle() throws {
        let f = try makeFixture()
        try write(f, "Weekend\nBring coffee and a thermos", on: try date(2026, 9, 28))

        XCTAssertEqual(titles(search(f, "thermos")), [["Weekend"]])
    }

    func testSearchMatchesATranscriptAndAVoiceMemosStoredTitle() async throws {
        let f = try makeFixture()
        try await record(f, on: try date(2026, 9, 28))
        try write(f, "Unrelated", on: try date(2026, 9, 27))

        // The transcript says "dentist" and the generated title says "Dentist and flights".
        XCTAssertEqual(titles(search(f, "book flights")), [["Dentist and flights"]])
        XCTAssertEqual(titles(search(f, "flights and")), [])
        XCTAssertEqual(titles(search(f, "Dentist and")), [["Dentist and flights"]])
    }

    func testSearchMatchesARenamedVoiceMemoTitleWhoseTranscriptDoesNotSayIt() async throws {
        let f = try makeFixture(transcript: "Nothing to see")
        let voice = try await record(f, on: try date(2026, 9, 28))
        f.store.renameMemo(id: voice.id, title: "Grocery run")

        XCTAssertEqual(titles(search(f, "grocery")), [["Grocery run"]])
    }

    func testTheVoiceMemoFallbackTitleIsNotSearchContent() async throws {
        let f = try makeFixture(transcript: "Nothing to see")
        f.model.availability = .unavailable(.deviceNotEligible)
        let voice = try await record(f, on: try date(2026, 9, 28))
        XCTAssertEqual(voice.title, "Voice memo")

        let page = search(f, "voice")

        XCTAssertTrue(page.groups.isEmpty)
        XCTAssertEqual(page.noResultsMessage, "No memos match \u{201C}voice\u{201D}")
    }

    func testPhotosAreNotSearched() throws {
        let f = try makeFixture()
        let photo = StoredPhoto(data: Data([1]), thumbnail: Data([2]))
        let memo = try XCTUnwrap(f.store.addWrittenMemo(text: "", photos: [photo]))
        XCTAssertEqual(memo.title, "Photo memo")

        XCTAssertTrue(search(f, "photo").groups.isEmpty)
    }

    func testResultsStayGroupedByDay() throws {
        let f = try makeFixture()
        try write(f, "Lake plan", on: try date(2026, 9, 29, 8))
        try write(f, "Lake notes", on: try date(2026, 9, 28, 8))
        try write(f, "Lake photos", on: try date(2026, 9, 28, 19))
        try write(f, "Mountain plan", on: try date(2026, 9, 28, 12))

        let page = search(f, "lake")

        XCTAssertEqual(page.groups.map(\.title), ["Today", "Yesterday"])
        XCTAssertEqual(titles(page), [["Lake plan"], ["Lake photos", "Lake notes"]])
    }

    func testAnEditedMemoIsFoundByItsNewTextAndNotItsOld() throws {
        let f = try makeFixture()
        let memo = try write(f, "Draft", on: try date(2026, 9, 20))

        f.store.editMemo(id: memo.id, text: "Final")

        XCTAssertEqual(titles(search(f, "final")), [["Final"]])
        XCTAssertTrue(search(f, "draft").groups.isEmpty)
    }

    func testPagingAppliesToSearchResults() throws {
        let f = try makeFixture()
        for day in 1...4 {
            try write(f, "Lake \(day)", on: try date(2026, 9, day))
        }
        try write(f, "Other", on: try date(2026, 9, 10))

        let page = f.store.memoGroups(matching: "lake", limit: 3)

        XCTAssertEqual(titles(page).flatMap { $0 }, ["Lake 4", "Lake 3", "Lake 2"])
        XCTAssertTrue(page.hasMore)
    }

    // MARK: No results

    func testNoResultsNamesTheSearch() throws {
        let f = try makeFixture()
        try write(f, "Weekend plan", on: try date(2026, 9, 28))

        let page = search(f, "  zebra ")

        XCTAssertTrue(page.groups.isEmpty)
        XCTAssertEqual(page.query, "zebra")
        XCTAssertEqual(page.noResultsMessage, "No memos match \u{201C}zebra\u{201D}")
    }

    func testABlankSearchListsEveryMemo() throws {
        let f = try makeFixture()
        try write(f, "One", on: try date(2026, 9, 28))
        try write(f, "Two", on: try date(2026, 9, 27))

        let page = search(f, "   ")

        XCTAssertEqual(titles(page).flatMap { $0 }, ["One", "Two"])
        XCTAssertNil(page.noResultsMessage)
    }

    // MARK: Snippets

    private let deepText = "Weekend\nWe talked about many things on the long drive home and finally the lake house came up with a proposal for August."

    func testAMatchDeepInTheTextShowsASnippetWithTheMatchHighlighted() throws {
        let f = try makeFixture()
        try write(f, deepText, on: try date(2026, 9, 28))

        let result = try XCTUnwrap(search(f, "LAKE").groups.first?.results.first)
        let snippet = try XCTUnwrap(result.snippet)

        XCTAssertTrue(snippet.text.hasPrefix("…"))
        XCTAssertTrue(snippet.text.contains("the lake house came up"))
        XCTAssertEqual(snippet.highlights.map { String(snippet.text[$0]) }, ["lake"])
        XCTAssertLessThan(snippet.text.count, deepText.count)
    }

    func testASnippetHighlightsEveryOccurrenceInIt() throws {
        let f = try makeFixture()
        try write(f, "Notes\nThe first paragraph says nothing about it at all, then a trail, another trail, and one more.", on: try date(2026, 9, 28))

        let snippet = try XCTUnwrap(search(f, "trail").groups.first?.results.first?.snippet)

        XCTAssertEqual(snippet.highlights.count, 2)
        XCTAssertTrue(snippet.highlights.allSatisfy { String(snippet.text[$0]) == "trail" })
    }

    func testASnippetMatchesIgnoringAccentsAndHighlightsTheTextAsWritten() throws {
        let f = try makeFixture()
        try write(f, "Notes\nThe first paragraph says nothing about it at all, then we met at the café by the river.", on: try date(2026, 9, 28))

        let snippet = try XCTUnwrap(search(f, "cafe").groups.first?.results.first?.snippet)

        XCTAssertEqual(snippet.highlights.map { String(snippet.text[$0]) }, ["café"])
    }

    func testAMatchDeepInATranscriptShowsASnippet() async throws {
        let transcript = "So this morning I was thinking about how the whole week has gone and what I want to change, mostly the commute and the meetings."
        let f = try makeFixture(transcript: transcript)
        try await record(f, on: try date(2026, 9, 28))

        let snippet = try XCTUnwrap(search(f, "commute").groups.first?.results.first?.snippet)

        XCTAssertEqual(snippet.highlights.map { String(snippet.text[$0]) }, ["commute"])
        XCTAssertTrue(snippet.text.hasPrefix("…"))
    }

    func testAMatchInTheTitleOrNearTheStartOfTheDetailHasNoSnippet() throws {
        let f = try makeFixture()
        try write(f, deepText, on: try date(2026, 9, 28))

        XCTAssertNil(search(f, "weekend").groups.first?.results.first?.snippet)
        XCTAssertNil(search(f, "talked").groups.first?.results.first?.snippet)
    }

    func testListingWithoutASearchCarriesNoSnippets() throws {
        let f = try makeFixture()
        try write(f, deepText, on: try date(2026, 9, 28))

        XCTAssertNil(search(f, "").groups.first?.results.first?.snippet)
    }

    func testASnippetNearTheEndOfTheTextHasNoTrailingEllipsis() throws {
        let f = try makeFixture()
        try write(f, "Notes\nThe first paragraph says nothing about it at all and then the end", on: try date(2026, 9, 28))

        let snippet = try XCTUnwrap(search(f, "end").groups.first?.results.first?.snippet)

        XCTAssertTrue(snippet.text.hasPrefix("…"))
        XCTAssertFalse(snippet.text.hasSuffix("…"))
        XCTAssertTrue(snippet.text.hasSuffix("the end"))
    }
}
