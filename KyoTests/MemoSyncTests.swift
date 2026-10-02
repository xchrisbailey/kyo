import SwiftData
import XCTest

/// Memo sync (ADR 0005, phone to Watch): a publishing phone `MemoStore` and a mirroring
/// `WatchMemoList` connected by a controllable transport. September 2026, UTC.
@MainActor
final class MemoSyncTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    private var phoneNow = Date()
    private var watchNow = Date()

    private func moment(_ day: Int, _ hour: Int = 9, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "MemoSyncTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func makePhone(
        _ transport: ControllableMemoTransport, defaults: UserDefaults? = nil, container: ModelContainer? = nil,
        transcriber: any VoiceTranscriber = NoTranscriber(), languageModel: any OnDeviceLanguageModel = NoLanguageModel()
    ) throws -> MemoStore {
        MemoStore(
            modelContainer: try container ?? KyoModelContainer.make(inMemory: true),
            now: { self.phoneNow }, calendar: calendar,
            transcriber: transcriber, languageModel: languageModel,
            memoSync: transport, userDefaults: try defaults ?? makeDefaults()
        )
    }

    private func makeWatch(_ transport: ControllableMemoTransport, defaults: UserDefaults? = nil) throws -> WatchMemoList {
        WatchMemoList(
            userDefaults: try defaults ?? makeDefaults(), now: { self.watchNow }, calendar: calendar, sync: transport
        )
    }

    private func voice(_ id: UUID = UUID(), at start: Date, duration: TimeInterval = 42) -> RecordedAudio {
        RecordedAudio(id: id, startedAt: start, duration: duration, data: Data([1, 2, 3]))
    }

    /// A row's detail line, with the narrow no-break space newer systems put before AM/PM
    /// normalized, so the assertions read like the spec.
    private func detail(_ memo: WatchMemo) -> String {
        memo.detailLine(locale: Locale(identifier: "en_US"), timeZone: calendar.timeZone)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    // MARK: Snapshot contents

    func testSnapshotCarriesEachOfTodaysMemosWithTheWatchRowFieldsAndNothingElse() async throws {
        phoneNow = try moment(29, 10)
        let transport = ControllableMemoTransport()
        let transcriber = ScriptedTranscriber()
        let model = FakeOnDeviceLanguageModel(availability: .available)
        model.titleAnswer = .title("Dentist and flights")
        let phone = try makePhone(transport, transcriber: transcriber, languageModel: model)

        let written = try XCTUnwrap(phone.addWrittenMemo(
            text: "An idea for the weekend\nTry the trail.",
            photos: [StoredPhoto(data: Data([1]), thumbnail: Data([2])), StoredPhoto(data: Data([3]), thumbnail: Data([4]))]
        ))
        let spoken = phone.addVoiceMemo(voice(at: try moment(29, 9, 41)), stoppedAtCap: false)
        transcriber.release(.transcript("Call the dentist and book flights"))
        await phone.transcriptionsSettled()

        let snapshot = try XCTUnwrap(transport.published.last)
        XCTAssertEqual(snapshot.memos.count, 2)
        let writtenEntry = try XCTUnwrap(snapshot.memos.first { $0.id == written.id })
        XCTAssertEqual(writtenEntry, WatchMemo(
            id: written.id, day: TaskCompletionDay(date: phoneNow, calendar: calendar), createdAt: phoneNow,
            kind: .written, title: "An idea for the weekend", voiceState: nil, duration: 0, photoCount: 2
        ))
        let spokenEntry = try XCTUnwrap(snapshot.memos.first { $0.id == spoken.id })
        XCTAssertEqual(spokenEntry, WatchMemo(
            id: spoken.id, day: TaskCompletionDay(date: try moment(29), calendar: calendar), createdAt: try moment(29, 9, 41),
            kind: .voice, title: "Dentist and flights", voiceState: .transcribed, duration: 42, photoCount: 0
        ))
        // No text, transcript, audio or photo bytes: the payload holds none of them.
        let payload = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for secret in ["Try the trail", "Call the dentist and book"] {
            XCTAssertFalse(payload.contains(secret), secret)
        }
        XCTAssertEqual(snapshot.acknowledgedMemoIDs, [])
    }

    func testFallbackTitlesAndVoiceStatesTravelInTheSnapshot() throws {
        phoneNow = try moment(29, 10)
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        let photoOnly = try XCTUnwrap(phone.addWrittenMemo(text: "", photos: [StoredPhoto(data: Data([1]), thumbnail: Data([2]))]))
        let recording = phone.addVoiceMemo(voice(at: phoneNow), stoppedAtCap: false)

        let entries = try XCTUnwrap(transport.published.last).memos
        XCTAssertEqual(entries.first { $0.id == photoOnly.id }?.title, "Photo memo")
        XCTAssertEqual(entries.first { $0.id == recording.id }?.title, "Voice memo")
        XCTAssertEqual(entries.first { $0.id == recording.id }?.voiceState, .transcribing)
    }

    func testOnlyTodaysMemosArePublished() throws {
        phoneNow = try moment(28, 22)
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        _ = phone.addWrittenMemo(text: "Yesterday's")

        phoneNow = try moment(29, 9)
        phone.refreshForCurrentDay()
        let today = try XCTUnwrap(phone.addWrittenMemo(text: "Today's"))

        XCTAssertEqual(try XCTUnwrap(transport.published.last).memos.map(\.id), [today.id])
    }

    func testSnapshotIsPublishedAtLaunchEvenWithNoMemos() throws {
        phoneNow = try moment(29)
        let transport = ControllableMemoTransport()
        _ = try makePhone(transport)

        XCTAssertEqual(transport.published.count, 1)
        XCTAssertEqual(transport.published.first?.memos, [])
    }

    // MARK: Republishing

    func testEveryMemoChangeRepublishes() throws {
        phoneNow = try moment(29, 10)
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        watchNow = phoneNow

        let memo = try XCTUnwrap(phone.addWrittenMemo(text: "Groceries"))
        XCTAssertEqual(watch.todayMemos.map(\.title), ["Groceries"])

        _ = phone.editMemo(id: memo.id, text: "Errands\nGroceries")
        XCTAssertEqual(watch.todayMemos.map(\.title), ["Errands"])

        _ = phone.addPhoto(StoredPhoto(data: Data([1]), thumbnail: Data([2])), toMemoID: memo.id)
        XCTAssertEqual(watch.todayMemos.map(\.photoCount), [1])

        _ = phone.deleteMemo(id: memo.id)
        XCTAssertEqual(watch.todayMemos, [])
        XCTAssertTrue(watch.hasSynced)
    }

    func testAVoiceMemoShowsTranscribingThenItsTranscriptTitle() async throws {
        phoneNow = try moment(29, 10)
        let transport = ControllableMemoTransport()
        let transcriber = ScriptedTranscriber()
        let model = FakeOnDeviceLanguageModel(availability: .available)
        model.titleAnswer = .title("Walk thoughts")
        let phone = try makePhone(transport, transcriber: transcriber, languageModel: model)
        let watch = try makeWatch(transport)
        watchNow = phoneNow

        _ = phone.addVoiceMemo(voice(at: phoneNow), stoppedAtCap: false)
        XCTAssertEqual(watch.todayMemos.map(\.voiceState), [.transcribing])
        XCTAssertEqual(detail(try XCTUnwrap(watch.todayMemos.first)), "Transcribing…")

        transcriber.release(.transcript("I thought about the walk"))
        await phone.transcriptionsSettled()
        XCTAssertEqual(watch.todayMemos.map(\.voiceState), [.transcribed])
        XCTAssertEqual(watch.todayMemos.map(\.title), ["Walk thoughts"])
    }

    func testRefreshWithNothingChangedPublishesNothing() throws {
        phoneNow = try moment(29, 10)
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        _ = phone.addWrittenMemo(text: "Groceries")
        let count = transport.published.count

        phone.refreshForCurrentDay()
        phone.refreshForCurrentDay()

        XCTAssertEqual(transport.published.count, count)
    }

    func testTheDayRollingOverRepublishesWithoutYesterdaysMemos() throws {
        phoneNow = try moment(29, 22)
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        _ = phone.addWrittenMemo(text: "Late thought")
        XCTAssertEqual(try XCTUnwrap(transport.published.last).memos.count, 1)

        phoneNow = try moment(30, 0, 1)
        phone.refreshForCurrentDay()

        XCTAssertEqual(try XCTUnwrap(transport.published.last).memos, [])
    }

    // MARK: Revisions

    func testRevisionsIncreaseWithEveryPublish() throws {
        phoneNow = try moment(29, 10)
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        _ = phone.addWrittenMemo(text: "One")
        _ = phone.addWrittenMemo(text: "Two")

        let revisions = transport.published.map(\.revision)
        XCTAssertEqual(revisions, revisions.sorted())
        XCTAssertEqual(Set(revisions).count, revisions.count)
    }

    func testRevisionNeverGoesBackAcrossRelaunchEvenIfTheClockDoes() throws {
        phoneNow = try moment(29, 10)
        let defaults = try makeDefaults()
        let container = try KyoModelContainer.make(inMemory: true)
        let first = ControllableMemoTransport()
        let phone = try makePhone(first, defaults: defaults, container: container)
        _ = phone.addWrittenMemo(text: "One")
        let last = try XCTUnwrap(first.published.last).revision

        phoneNow = try moment(28, 10)
        let second = ControllableMemoTransport()
        _ = try makePhone(second, defaults: defaults, container: container)

        XCTAssertGreaterThan(try XCTUnwrap(second.published.first).revision, last)
    }

    func testWatchIgnoresAStaleOrDuplicateSnapshot() throws {
        phoneNow = try moment(29, 10)
        watchNow = phoneNow
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        _ = phone.addWrittenMemo(text: "One")
        let older = try XCTUnwrap(transport.published.last)
        _ = phone.addWrittenMemo(text: "Two")
        XCTAssertEqual(watch.todayMemos.count, 2)

        transport.deliver(older)
        XCTAssertEqual(watch.todayMemos.count, 2)

        transport.deliver(try XCTUnwrap(transport.published.last))
        XCTAssertEqual(watch.todayMemos.count, 2)
    }

    func testWatchCatchesUpOnReconnectFromTheLatestSnapshot() throws {
        phoneNow = try moment(29, 10)
        watchNow = phoneNow
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        transport.disconnect()
        _ = phone.addWrittenMemo(text: "One")
        _ = phone.addWrittenMemo(text: "Two")
        XCTAssertEqual(watch.todayMemos, [])

        transport.reconnect()

        XCTAssertEqual(watch.todayMemos.count, 2)
    }

    // MARK: Watch Today filter and cache

    func testWatchShowsOnlyMemosWhoseDayIsItsOwnTodayNewestFirst() throws {
        phoneNow = try moment(29, 23, 50)
        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        watchNow = try moment(29, 23, 55)
        _ = phone.addWrittenMemo(text: "First")
        phoneNow = try moment(29, 23, 52)
        _ = phone.addWrittenMemo(text: "Second")
        watch.refreshForCurrentDay()
        XCTAssertEqual(watch.todayMemos.map(\.title), ["Second", "First"])

        // Midnight passes on the Watch; the phone isn't running.
        watchNow = try moment(30, 0, 1)
        watch.refreshForCurrentDay()
        XCTAssertEqual(watch.todayMemos, [])
        XCTAssertTrue(watch.hasSynced)
    }

    func testWatchIsNotSyncedUntilASnapshotArrivesAndRemembersTheLastOne() throws {
        phoneNow = try moment(29, 10)
        watchNow = phoneNow
        let defaults = try makeDefaults()
        let watch = try makeWatch(ControllableMemoTransport(), defaults: defaults)
        XCTAssertFalse(watch.hasSynced)
        XCTAssertEqual(watch.todayMemos, [])

        let transport = ControllableMemoTransport()
        let phone = try makePhone(transport)
        let connected = try makeWatch(transport, defaults: defaults)
        _ = phone.addWrittenMemo(text: "Cached")
        XCTAssertEqual(connected.todayMemos.map(\.title), ["Cached"])

        // A new Watch launch with no connection still shows the cached memos.
        let offline = try makeWatch(ControllableMemoTransport(), defaults: defaults)
        XCTAssertTrue(offline.hasSynced)
        XCTAssertEqual(offline.todayMemos.map(\.title), ["Cached"])
    }

    // MARK: Row text

    func testDetailLinesFollowTheSpecWording() throws {
        let day = TaskCompletionDay(date: try moment(29), calendar: calendar)
        let time = try moment(29, 9, 41)
        func memo(_ kind: Memo.Kind, _ state: Memo.TranscriptState?, duration: TimeInterval = 0, photos: Int = 0) -> WatchMemo {
            WatchMemo(id: UUID(), day: day, createdAt: time, kind: kind, title: "T", voiceState: state, duration: duration, photoCount: photos)
        }

        XCTAssertEqual(detail(memo(.voice, .transcribed, duration: 42, photos: 2)), "9:41 AM · 0:42 · 2 photos")
        XCTAssertEqual(detail(memo(.voice, .transcribed, duration: 42, photos: 1)), "9:41 AM · 0:42 · 1 photo")
        XCTAssertEqual(detail(memo(.voice, .transcribed, duration: 600)), "9:41 AM · 10:00")
        XCTAssertEqual(detail(memo(.written, nil)), "9:41 AM")
        XCTAssertEqual(detail(memo(.written, nil, photos: 3)), "9:41 AM · 3 photos")
        XCTAssertEqual(detail(memo(.voice, .transcribing, duration: 42)), "Transcribing…")
        XCTAssertEqual(detail(memo(.voice, .noTranscript, duration: 42)), "No transcript")
    }

    func testAccessibilityLabelNamesKindTitleTimeAndDurationOrState() throws {
        let day = TaskCompletionDay(date: try moment(29), calendar: calendar)
        let entry = WatchMemo(
            id: UUID(), day: day, createdAt: try moment(29, 9, 41), kind: .voice, title: "Walk",
            voiceState: .noTranscript, duration: 42, photoCount: 2
        )

        let label = entry.accessibilityLabel(locale: Locale(identifier: "en_US"), timeZone: calendar.timeZone)
            .replacingOccurrences(of: "\u{202F}", with: " ")

        XCTAssertEqual(label, "Voice memo, Walk, 9:41 AM, 0:42, No transcript, 2 photos")
    }

    // MARK: Snapshot compatibility

    func testASnapshotWithoutAcknowledgedMemoIDsDecodesAsEmpty() throws {
        let json = #"{"revision": 7, "memos": []}"#

        let snapshot = try JSONDecoder().decode(MemoListSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.revision, 7)
        XCTAssertEqual(snapshot.acknowledgedMemoIDs, [])
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let entry = WatchMemo(
            id: UUID(), day: TaskCompletionDay(date: try moment(29), calendar: calendar), createdAt: try moment(29, 9, 41),
            kind: .voice, title: "Walk", voiceState: .transcribed, duration: 42, photoCount: 2
        )
        let snapshot = MemoListSnapshot(revision: 9, memos: [entry], acknowledgedMemoIDs: [UUID()])

        let decoded = try JSONDecoder().decode(MemoListSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded, snapshot)
    }
}
