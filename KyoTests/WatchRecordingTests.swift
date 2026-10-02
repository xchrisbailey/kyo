import SwiftData
import XCTest

/// Watch recording (ADR 0005, Watch to phone): a Watch `VoiceRecordingSession`, outbox and
/// `WatchMemoList` and a phone `MemoStore`, connected by a controllable file-transfer seam and a
/// controllable memo snapshot transport. Real file transfer doesn't work in the Simulator, so it's
/// checked on a paired iPhone and Watch. September 2026.
@MainActor
final class WatchRecordingTests: XCTestCase {
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    /// Everything the two devices share across a relaunch of either: their stored state, the
    /// phone's database, and the two transports between them.
    @MainActor
    private final class Link {
        let watchCalendar: Calendar
        let phoneCalendar: Calendar
        let watchClock: Clock
        let phoneClock: Clock
        let watchDefaults: UserDefaults
        let phoneDefaults: UserDefaults
        let outboxDirectory: URL
        let inboxDirectory: URL
        let container: ModelContainer
        let snapshots = ControllableMemoTransport()
        let files: ControllableMemoFileTransport
        let recorder = FakeAudioRecorder()
        let transcriber = ScriptedTranscriber()

        init(
            watchCalendar: Calendar, phoneCalendar: Calendar, start: Date, files: ControllableMemoFileTransport,
            watchDefaults: UserDefaults, phoneDefaults: UserDefaults, container: ModelContainer
        ) {
            self.watchCalendar = watchCalendar
            self.phoneCalendar = phoneCalendar
            self.watchClock = Clock(start)
            self.phoneClock = Clock(start)
            self.files = files
            self.watchDefaults = watchDefaults
            self.phoneDefaults = phoneDefaults
            self.container = container
            let root = FileManager.default.temporaryDirectory.appending(path: "WatchRecordingTests-\(UUID().uuidString)")
            outboxDirectory = root.appending(path: "outbox", directoryHint: .isDirectory)
            inboxDirectory = root.appending(path: "inbox", directoryHint: .isDirectory)
        }

        /// The recordings' files in the Watch's outbox folder.
        var outboxFiles: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: outboxDirectory.path)) ?? []).sorted()
        }

        var inboxFiles: [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: inboxDirectory.path)) ?? []
        }
    }

    private struct Watch {
        let outbox: WatchRecordingOutbox
        let list: WatchMemoList
        let session: VoiceRecordingSession
    }

    private static func utc(offsetHours: Int = 0) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offsetHours * 3600) ?? .gmt
        return calendar
    }

    private func moment(_ day: Int, _ hour: Int = 9, _ minute: Int = 0, _ second: Int = 0) throws -> Date {
        try XCTUnwrap(Self.utc().date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second
        )))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WatchRecordingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func makeLink(
        at start: Date? = nil, phoneOffsetHours: Int = 0, session isActivated: Bool = true
    ) throws -> Link {
        let link = Link(
            watchCalendar: Self.utc(), phoneCalendar: Self.utc(offsetHours: phoneOffsetHours),
            start: try start ?? moment(29, 9, 41),
            files: ControllableMemoFileTransport(isActivated: isActivated),
            watchDefaults: try makeDefaults(), phoneDefaults: try makeDefaults(),
            container: try KyoModelContainer.make(inMemory: true)
        )
        let root = link.outboxDirectory.deletingLastPathComponent()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return link
    }

    /// The Watch app starting up: its outbox (which resends what's unsent), the memo list, and a
    /// recording session.
    private func launchWatch(_ link: Link) -> Watch {
        let outbox = WatchRecordingOutbox(
            userDefaults: link.watchDefaults, directory: link.outboxDirectory,
            calendar: link.watchCalendar, transport: link.files
        )
        let list = WatchMemoList(
            userDefaults: link.watchDefaults, now: { link.watchClock.now }, calendar: link.watchCalendar,
            outbox: outbox, sync: link.snapshots
        )
        let session = VoiceRecordingSession(recorder: link.recorder, memos: outbox, now: { link.watchClock.now })
        return Watch(outbox: outbox, list: list, session: session)
    }

    /// The phone app starting up: its memo store, receiving Watch recordings.
    private func launchPhone(_ link: Link) -> MemoStore {
        MemoStore(
            modelContainer: link.container, now: { link.phoneClock.now }, calendar: link.phoneCalendar,
            transcriber: link.transcriber, memoSync: link.snapshots, watchRecordings: link.files,
            watchInbox: WatchRecordingInbox(directory: link.inboxDirectory), userDefaults: link.phoneDefaults
        )
    }

    /// Lets the main-actor work a delivery starts finish.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    /// Records for `seconds` on the Watch and stops; returns the memo's id.
    @discardableResult
    private func record(_ watch: Watch, _ link: Link, seconds: TimeInterval = 42) async throws -> UUID {
        await watch.session.begin()
        link.watchClock.advance(seconds)
        watch.session.tick()
        watch.session.stop()
        guard case .saved(let memo, _)? = watch.session.outcome else {
            XCTFail("Expected a saved recording, got \(String(describing: watch.session.outcome))")
            throw XCTSkip("nothing saved")
        }
        return memo.id
    }

    private func row(_ memo: WatchListedMemo, _ link: Link) -> String {
        memo.detailLine(locale: Locale(identifier: "en_US"), timeZone: link.watchCalendar.timeZone)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    // MARK: Outbox before transfer

    func testTheOutboxEntryAndFileAreWrittenBeforeTheTransferStarts() async throws {
        let link = try makeLink(at: try moment(29, 9, 41))
        let watch = launchWatch(link)
        link.files.disconnect()
        var entriesStoredAtTransfer: [WatchRecordingEntry] = []
        var fileExistedAtTransfer = false
        link.files.onTransfer = { _, file in
            entriesStoredAtTransfer = (link.watchDefaults.data(forKey: WatchRecordingOutbox.storageKey)
                .flatMap { try? JSONDecoder().decode([WatchRecordingEntry].self, from: $0) }) ?? []
            fileExistedAtTransfer = FileManager.default.fileExists(atPath: file.path)
        }

        let id = try await record(watch, link, seconds: 42)

        let expected = WatchRecordingEntry(
            id: id, startedAt: try moment(29, 9, 41), day: TaskCompletionDay(date: try moment(29), calendar: link.watchCalendar),
            duration: 42
        )
        XCTAssertEqual(entriesStoredAtTransfer, [expected])
        XCTAssertTrue(fileExistedAtTransfer)
        XCTAssertEqual(link.files.transferCalls.map(\.entry), [expected])
        XCTAssertEqual(link.files.transferCalls.first?.data, link.recorder.recordedBytes)
        XCTAssertEqual(link.outboxFiles, ["\(id.uuidString).caf"])
    }

    func testTransferIsCalledOnlyOnceTheSessionHasActivated() async throws {
        let link = try makeLink(session: false)
        let watch = launchWatch(link)

        let id = try await record(watch, link)
        // Recorded and written, but not sent: the recording waits in the outbox, in the list.
        XCTAssertEqual(link.files.transferCalls.count, 0)
        XCTAssertEqual(watch.outbox.entries.map(\.id), [id])
        XCTAssertEqual(watch.list.waitingRecordings.map(\.id), [id])

        link.files.activate()
        XCTAssertEqual(link.files.transferCalls.map(\.entry.id), [id])
        XCTAssertEqual(link.files.callsBeforeActivation, 0)
    }

    func testTheMetadataHoldsOnlyPropertyListTypesAndRoundTrips() throws {
        let entry = WatchRecordingEntry(
            id: UUID(), startedAt: try moment(29, 9, 41), day: TaskCompletionDay(date: try moment(29), calendar: Self.utc()), duration: 42
        )
        let metadata = entry.metadata()
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0))
        XCTAssertEqual(WatchRecordingEntry(metadata: metadata), entry)
        XCTAssertNil(WatchRecordingEntry(metadata: ["something": "else"]))
        XCTAssertNil(WatchRecordingEntry(metadata: nil))
    }

    // MARK: Delivery

    func testTheSystemDeletesTheFileWhenTheReceiverReturnsSoThePhoneMovesItFirst() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)

        let id = try await record(watch, link)
        await settle()

        XCTAssertEqual(link.files.receivedFileSurvivedReceiver, [false])
        XCTAssertEqual(phone.audioData(forMemoID: id), link.recorder.recordedBytes)
        XCTAssertEqual(link.inboxFiles, [], "The inbox is emptied once the memo is saved")
    }

    func testTheMemoIsCreatedAsTranscribingAndThenTranscribed() async throws {
        let link = try makeLink(at: try moment(29, 9, 41))
        let watch = launchWatch(link)
        let phone = launchPhone(link)

        let id = try await record(watch, link, seconds: 42)
        await settle()

        let memo = try XCTUnwrap(phone.memo(id: id))
        XCTAssertEqual(memo.kind, .voice)
        XCTAssertEqual(memo.transcriptState, .transcribing)
        XCTAssertEqual(memo.duration, 42)
        XCTAssertEqual(memo.createdAt, try moment(29, 9, 41))
        XCTAssertEqual(phone.memos.map(\.id), [id])

        link.transcriber.release(.transcript("Call the dentist"))
        await phone.transcriptionsSettled()
        XCTAssertEqual(link.transcriber.transcribedIDs, [id])
        XCTAssertEqual(phone.memo(id: id)?.transcriptState, .transcribed)
        XCTAssertEqual(phone.memo(id: id)?.text, "Call the dentist")
    }

    func testARecordingThatReachedTheCapShowsTheCapNoteOnThePhone() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)

        await watch.session.begin()
        link.watchClock.advance(VoiceRecordingSession.cap + 5)
        watch.session.tick()
        await settle()

        guard case .saved(let saved, reachedCap: true)? = watch.session.outcome else {
            return XCTFail("Expected the recording to stop at the cap")
        }
        XCTAssertEqual(link.files.transferCalls.first?.entry.duration, VoiceRecordingSession.cap)
        XCTAssertEqual(phone.memo(id: saved.id)?.capNote, "Recording stopped at 10 minutes")
    }

    func testTheMemoBelongsToTheWatchsDayNotTheDayThePhoneReceivedIt() async throws {
        // The phone is ten hours ahead of the Watch. The Watch starts recording at 23:50 on
        // September 29 and the phone gets it at 00:10 UTC, already September 30 there.
        let link = try makeLink(at: try moment(29, 23, 50), phoneOffsetHours: 10)
        let watch = launchWatch(link)
        let phone = launchPhone(link)
        link.files.disconnect()
        let id = try await record(watch, link, seconds: 30)
        link.phoneClock.now = try moment(30, 0, 10)
        phone.refreshForCurrentDay()

        link.files.reconnect()
        await settle()

        let memo = try XCTUnwrap(phone.memo(id: id))
        XCTAssertEqual(memo.day, TaskCompletionDay(date: try moment(29, 23, 50), calendar: link.watchCalendar))
        XCTAssertEqual(memo.day.day, 29)
        XCTAssertEqual(memo.createdAt, try moment(29, 23, 50))
        // The phone's own calendar would have put its start on the 30th, and its Today is the 30th.
        XCTAssertEqual(TaskCompletionDay(date: memo.createdAt, calendar: link.phoneCalendar).day, 30)
        XCTAssertEqual(phone.memos, [], "It isn't one of the phone's Today memos")
        XCTAssertTrue(try XCTUnwrap(link.snapshots.published.last).acknowledgedMemoIDs.contains(id))
    }

    func testARecordingDeliveredWhileTheWatchWasOutOfReachArrivesOnReconnect() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)
        link.files.disconnect()

        let id = try await record(watch, link)
        await settle()
        XCTAssertNil(phone.memo(id: id))
        XCTAssertEqual(link.files.outstandingRecordingIDs, [id])

        link.files.reconnect()
        await settle()
        XCTAssertNotNil(phone.memo(id: id))
        XCTAssertEqual(link.files.outstandingRecordingIDs, [])
    }

    // MARK: Acknowledgment and cleanup

    func testTheMemoSnapshotAcknowledgesTheRecordingAndTheWatchCleansUp() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)

        let id = try await record(watch, link)
        await settle()

        XCTAssertEqual(try XCTUnwrap(link.snapshots.published.last).acknowledgedMemoIDs, [id])
        XCTAssertEqual(watch.outbox.entries, [])
        XCTAssertEqual(link.outboxFiles, [])
        XCTAssertEqual(link.watchDefaults.data(forKey: WatchRecordingOutbox.storageKey).flatMap {
            try? JSONDecoder().decode([WatchRecordingEntry].self, from: $0)
        }, [])
        // The phone's version replaces the waiting row.
        XCTAssertEqual(watch.list.waitingRecordings, [])
        XCTAssertEqual(watch.list.listedMemos.map(\.id), [id])
        XCTAssertEqual(watch.list.todayMemos.first?.voiceState, .transcribing)
        XCTAssertEqual(phone.memos.map(\.id), [id])
    }

    func testAFinishedTransferIsNotDeliveryOnlyTheAcknowledgmentRetiresTheRecording() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)
        link.snapshots.disconnect()

        let id = try await record(watch, link)
        await settle()
        // The transfer finished without an error, and the phone has the memo...
        XCTAssertNotNil(phone.memo(id: id))
        XCTAssertEqual(link.files.outstandingRecordingIDs, [])
        // ...but the Watch hasn't heard, so it keeps the file and the entry, and the waiting row.
        XCTAssertEqual(watch.outbox.entries.map(\.id), [id])
        XCTAssertEqual(link.outboxFiles, ["\(id.uuidString).caf"])
        XCTAssertEqual(watch.list.waitingRecordings.map(\.id), [id])

        link.snapshots.reconnect()
        XCTAssertEqual(watch.outbox.entries, [])
        XCTAssertEqual(link.outboxFiles, [])
        XCTAssertEqual(watch.list.waitingRecordings, [])
    }

    func testAFinishWithoutErrorWhenThePhoneNeverStoredItKeepsTheRecording() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        let id = try await record(watch, link)

        link.files.finishWithoutDelivery(id)

        XCTAssertEqual(watch.outbox.entries.map(\.id), [id])
        XCTAssertEqual(link.outboxFiles, ["\(id.uuidString).caf"])
        XCTAssertEqual(link.files.transferCalls.count, 1, "A finish without an error isn't retried")
    }

    func testAnAcknowledgmentInAStaleSnapshotStillRetiresTheRecording() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        let id = try await record(watch, link)
        let day = TaskCompletionDay(date: link.watchClock.now, calendar: link.watchCalendar)

        link.snapshots.deliver(MemoListSnapshot(revision: 100, memos: [
            WatchMemo(id: UUID(), day: day, createdAt: link.watchClock.now, kind: .written, title: "Newer")
        ]))
        link.snapshots.deliver(MemoListSnapshot(revision: 50, memos: [], acknowledgedMemoIDs: [id]))

        XCTAssertEqual(watch.outbox.entries, [])
        XCTAssertEqual(watch.list.todayMemos.map(\.title), ["Newer"], "The older list itself isn't applied")
    }

    func testAnAcknowledgmentCachedBeforeAQuitRetiresTheRecordingAtLaunch() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        let id = try await record(watch, link)
        // The Watch quit after caching a memo snapshot that confirms the recording, but before
        // it retired the entry.
        link.watchDefaults.set(
            try JSONEncoder().encode(MemoListSnapshot(revision: 100, memos: [], acknowledgedMemoIDs: [id])),
            forKey: WatchMemoList.storageKey
        )

        let relaunched = launchWatch(link)

        XCTAssertEqual(relaunched.outbox.entries, [])
        XCTAssertEqual(link.outboxFiles, [])
    }

    func testASnapshotTheTransportAlreadyHoldsRetiresAcknowledgedRecordingsWhenTheStoresAreMade() async throws {
        // A background launch: the phone's snapshot arrived while the Watch app wasn't open. The
        // Watch has no view yet, only the stores, and the transport hands over what it holds.
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)
        link.snapshots.disconnect()
        let id = try await record(watch, link)
        await settle()
        XCTAssertNotNil(phone.memo(id: id))
        XCTAssertEqual(link.outboxFiles, ["\(id.uuidString).caf"])
        // The first Watch process is gone; nothing receives the snapshot until the next launch.
        link.snapshots.setMemoSnapshotHandler { _ in }
        link.snapshots.reconnect()
        XCTAssertEqual(link.outboxFiles, ["\(id.uuidString).caf"])

        let woken = launchWatch(link)

        XCTAssertEqual(woken.outbox.entries, [])
        XCTAssertEqual(link.outboxFiles, [])
        XCTAssertEqual(woken.list.listedMemos.map(\.id), [id])
    }

    // MARK: Retry

    func testAFailedTransferIsSentAgainAndAGivenUpOneWaitsForTheNextLaunch() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        let id = try await record(watch, link)
        XCTAssertEqual(link.files.transferCalls.count, 1)

        link.files.fail(id)
        XCTAssertEqual(link.files.transferCalls.count, 2)
        link.files.fail(id)
        link.files.fail(id)
        XCTAssertEqual(link.files.transferCalls.count, 4)
        // Always failing: it stops spinning, and the recording stays in the outbox.
        link.files.fail(id)
        XCTAssertEqual(link.files.transferCalls.count, 4)
        XCTAssertEqual(watch.outbox.entries.map(\.id), [id])

        _ = launchWatch(link)
        XCTAssertEqual(link.files.transferCalls.count, 5)
    }

    func testAtLaunchTheWatchResendsWhatIsNotOutstandingAndNothingElse() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        let queued = try await record(watch, link)
        link.watchClock.advance(60)
        let finished = try await record(watch, link)
        link.files.finishWithoutDelivery(finished)
        XCTAssertEqual(link.files.transferCalls.count, 2)

        // Relaunch: `queued` is still with the system, `finished` isn't.
        _ = launchWatch(link)

        XCTAssertEqual(link.files.transferCalls.map(\.entry.id), [queued, finished, finished])
    }

    func testAResentRecordingNeverDuplicatesTheMemo() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)
        link.snapshots.disconnect()
        let id = try await record(watch, link)
        await settle()

        // The Watch never heard, so a relaunch sends the recording again.
        _ = launchWatch(link)
        await settle()

        XCTAssertEqual(link.files.transferCalls.count, 2)
        XCTAssertEqual(phone.memos.map(\.id), [id])
        XCTAssertEqual(link.inboxFiles, [])
    }

    // MARK: Duplicates and deletion

    func testARepeatDeliveryIsIgnoredButStillAcknowledged() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)
        let id = try await record(watch, link)
        await settle()
        let publishedBefore = link.snapshots.published.count

        link.files.deliverAgain(id)
        await settle()

        XCTAssertEqual(phone.memos.map(\.id), [id])
        XCTAssertGreaterThan(link.snapshots.published.count, publishedBefore, "The acknowledgment is published again")
        XCTAssertEqual(try XCTUnwrap(link.snapshots.published.last).acknowledgedMemoIDs, [id])
        XCTAssertEqual(link.inboxFiles, [])
    }

    func testAMemoDeletedOnThePhoneNeverComesBackWhenItIsDeliveredAgain() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)
        let id = try await record(watch, link)
        await settle()
        XCTAssertNotNil(phone.deleteMemo(id: id))
        XCTAssertEqual(phone.memos, [])

        link.files.deliverAgain(id)
        await settle()

        XCTAssertNil(phone.memo(id: id))
        XCTAssertEqual(phone.memos, [])
        XCTAssertEqual(try XCTUnwrap(link.snapshots.published.last).acknowledgedMemoIDs, [id])
        XCTAssertEqual(try XCTUnwrap(link.snapshots.published.last).memos, [])
    }

    func testReceivedIDsSurviveARelaunchOfThePhone() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let first = launchPhone(link)
        let id = try await record(watch, link)
        await settle()
        first.deleteMemo(id: id)

        let relaunched = launchPhone(link)
        link.files.deliverAgain(id)
        await settle()

        XCTAssertNil(relaunched.memo(id: id))
        XCTAssertEqual(try XCTUnwrap(link.snapshots.published.last).acknowledgedMemoIDs, [id])
        // A Watch-link record, so it's in UserDefaults and not the database.
        XCTAssertNotNil(link.phoneDefaults.data(forKey: MemoStore.receivedWatchRecordingIDsKey))
    }

    func testTheSetOfReceivedIDsIsBounded() async throws {
        let link = try makeLink()
        let phone = launchPhone(link)
        let day = TaskCompletionDay(date: link.watchClock.now, calendar: link.watchCalendar)
        let limit = MemoStore.maxReceivedWatchRecordingIDs
        let entries = (0...limit).map { offset in
            WatchRecordingEntry(id: UUID(), startedAt: link.watchClock.now.addingTimeInterval(Double(offset)), day: day, duration: 1)
        }

        for entry in entries {
            link.files.deliver(entry)
            await settle()
        }

        let acknowledged = try XCTUnwrap(link.snapshots.published.last).acknowledgedMemoIDs
        XCTAssertEqual(acknowledged.count, limit)
        XCTAssertFalse(acknowledged.contains(entries[0].id), "The oldest id is forgotten")
        XCTAssertTrue(acknowledged.contains(entries[limit].id))
        XCTAssertEqual(phone.memos.count, limit + 1)
    }

    func testARecordingLeftInTheInboxByAQuitBecomesAMemoAtTheNextLaunch() async throws {
        let link = try makeLink()
        let entry = WatchRecordingEntry(
            id: UUID(), startedAt: try moment(29, 8, 0),
            day: TaskCompletionDay(date: try moment(29, 8, 0), calendar: link.watchCalendar), duration: 12
        )
        // Moved out of the system's inbox, then the app quit before the memo was saved.
        let received = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        try Data([9, 9]).write(to: received)
        XCTAssertTrue(WatchRecordingInbox(directory: link.inboxDirectory).keep(ReceivedWatchRecording(file: received, entry: entry)))

        let phone = launchPhone(link)

        XCTAssertEqual(phone.audioData(forMemoID: entry.id), Data([9, 9]))
        XCTAssertEqual(phone.memo(id: entry.id)?.transcriptState, .transcribing)
        XCTAssertEqual(try XCTUnwrap(link.snapshots.published.last).acknowledgedMemoIDs, [entry.id])
        XCTAssertEqual(link.inboxFiles, [])
    }

    func testARecordingThatArrivesBeforeThePhoneIsReadyWaitsForIt() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let id = try await record(watch, link)
        XCTAssertEqual(link.files.outstandingRecordingIDs, [id])

        let phone = launchPhone(link)
        await settle()

        XCTAssertNotNil(phone.memo(id: id))
        XCTAssertEqual(watch.outbox.entries, [])
    }

    // MARK: Waiting rows

    func testAnUnconfirmedRecordingShowsAtOnceAsWaitingForIPhone() async throws {
        let link = try makeLink(at: try moment(29, 9, 41))
        let watch = launchWatch(link)
        link.files.disconnect()

        let id = try await record(watch, link, seconds: 42)

        let waiting = try XCTUnwrap(watch.list.listedMemos.first)
        XCTAssertEqual(watch.list.listedMemos.count, 1)
        XCTAssertEqual(waiting.id, id)
        XCTAssertEqual(waiting.title, "Voice memo")
        XCTAssertEqual(row(waiting, link), "9:41 AM · Waiting for iPhone")
        XCTAssertEqual(
            waiting.accessibilityLabel(locale: Locale(identifier: "en_US"), timeZone: link.watchCalendar.timeZone)
                .replacingOccurrences(of: "\u{202F}", with: " "),
            "Voice memo, Voice memo, 9:41 AM · Waiting for iPhone"
        )
        XCTAssertEqual(watch.list.todayMemos, [], "It isn't one of the phone's memos yet")
    }

    func testRecordingWorksOnAWatchThatHasNeverSynced() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()

        XCTAssertFalse(watch.list.hasSynced)
        let id = try await record(watch, link)

        XCTAssertFalse(watch.list.hasSynced)
        XCTAssertEqual(watch.list.listedMemos.map(\.id), [id])
        XCTAssertEqual(watch.outbox.entries.map(\.id), [id])
    }

    func testWaitingRecordingsAreListedNewestFirstWithTheConfirmedMemosAndKeepTheirTime() async throws {
        let link = try makeLink(at: try moment(29, 9, 0))
        let watch = launchWatch(link)
        link.files.disconnect()
        let day = TaskCompletionDay(date: try moment(29), calendar: link.watchCalendar)
        link.snapshots.deliver(MemoListSnapshot(revision: 1, memos: [
            WatchMemo(id: UUID(), day: day, createdAt: try moment(29, 8, 0), kind: .written, title: "Earlier"),
            WatchMemo(id: UUID(), day: day, createdAt: try moment(29, 9, 30), kind: .written, title: "Later"),
        ]))
        link.watchClock.now = try moment(29, 9, 10)
        _ = try await record(watch, link, seconds: 5)

        XCTAssertEqual(watch.list.listedMemos.map(\.title), ["Later", "Voice memo", "Earlier"])
    }

    func testAWaitingRecordingFromAnotherDayIsNotListedOnTodayButIsStillSent() async throws {
        let link = try makeLink(at: try moment(29, 23, 50))
        let watch = launchWatch(link)
        link.files.disconnect()
        let id = try await record(watch, link, seconds: 30)
        XCTAssertEqual(watch.list.listedMemos.map(\.id), [id])

        link.watchClock.now = try moment(30, 0, 5)
        watch.list.refreshForCurrentDay()

        XCTAssertEqual(watch.list.listedMemos, [])
        XCTAssertEqual(watch.outbox.entries.map(\.id), [id])
    }

    func testTheOutboxSurvivesARelaunchOfTheWatchAndShowsTheWaitingRow() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        let id = try await record(watch, link)

        let relaunched = launchWatch(link)

        XCTAssertEqual(relaunched.outbox.entries.map(\.id), [id])
        XCTAssertEqual(relaunched.list.waitingRecordings.map(\.id), [id])
        XCTAssertEqual(link.outboxFiles, ["\(id.uuidString).caf"])
    }

    // MARK: Recorder edge cases

    func testACrashedRecordingGoesIntoTheOutboxAndIsSent() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        let partial = RecordedAudio(id: UUID(), startedAt: try moment(29, 8, 15), duration: 17, data: Data([5, 5, 5]))
        link.recorder.partialRecordings = [partial]

        let recovered = watch.session.recoverInterruptedRecordings()

        XCTAssertEqual(recovered.map(\.id), [partial.id])
        XCTAssertEqual(watch.outbox.entries.map(\.id), [partial.id])
        XCTAssertEqual(watch.outbox.entries.first?.duration, 17)
        XCTAssertEqual(watch.outbox.entries.first?.startedAt, try moment(29, 8, 15))
        XCTAssertEqual(link.files.transferCalls.map(\.entry.id), [partial.id])
        XCTAssertEqual(link.files.transferCalls.first?.data, Data([5, 5, 5]))
        XCTAssertEqual(link.recorder.removedFileIDs, [partial.id])
    }

    func testDiscardSavesNothingAndSendsNothing() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        await watch.session.begin()
        link.watchClock.advance(10)

        watch.session.discard()

        XCTAssertEqual(watch.outbox.entries, [])
        XCTAssertEqual(link.files.transferCalls.count, 0)
        XCTAssertEqual(link.outboxFiles, [])
        XCTAssertEqual(watch.session.outcome, .discarded)
    }

    func testMicrophoneDeniedSavesNothing() async throws {
        let link = try makeLink()
        link.recorder.microphoneAccess = .denied
        let watch = launchWatch(link)

        await watch.session.begin()

        XCTAssertEqual(watch.session.phase, .microphoneDenied)
        XCTAssertEqual(watch.outbox.entries, [])
        XCTAssertEqual(link.files.transferCalls.count, 0)
        XCTAssertEqual(watch.list.listedMemos, [])
    }

    func testOutOfSpaceAtTheStartRecordsNothing() async throws {
        let link = try makeLink()
        link.recorder.startError = AudioRecordingError.outOfSpace
        let watch = launchWatch(link)

        await watch.session.begin()

        XCTAssertEqual(watch.session.phase, .couldNotRecord)
        XCTAssertEqual(watch.session.failure, .outOfSpace)
        XCTAssertEqual(watch.outbox.entries, [])
        XCTAssertEqual(link.files.transferCalls.count, 0)
    }

    func testOutOfSpaceWhenSavingKeepsNothingAndLeavesNoPartialFileToComeBack() async throws {
        let link = try makeLink()
        // A file sits where the outbox folder should be, so nothing can be written there.
        try FileManager.default.createDirectory(
            at: link.outboxDirectory.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: link.outboxDirectory)
        let watch = launchWatch(link)
        await watch.session.begin()
        link.watchClock.advance(20)
        watch.session.tick()

        watch.session.stop()

        XCTAssertEqual(watch.session.phase, .couldNotRecord)
        XCTAssertEqual(watch.session.failure, .outOfSpace)
        XCTAssertNil(watch.session.outcome)
        XCTAssertEqual(watch.outbox.entries, [])
        XCTAssertEqual(link.files.transferCalls.count, 0)
        XCTAssertEqual(link.recorder.removedFileIDs.count, 1)
        XCTAssertEqual(watch.list.listedMemos, [])
    }

    func testAnInterruptionPausesAndResumeThenStopSavesOneRecording() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        await watch.session.begin()
        link.watchClock.advance(10)
        watch.session.tick()

        link.recorder.simulateInterruption()
        XCTAssertEqual(watch.session.phase, .paused)
        link.watchClock.advance(300)
        await watch.session.resume()
        link.watchClock.advance(5)
        watch.session.stop()

        XCTAssertEqual(watch.outbox.entries.count, 1)
        XCTAssertEqual(watch.outbox.entries.first?.duration, 15, "The pause isn't counted")
    }

    func testTheCapWarningShowsInTheLast30SecondsBeforeTheAutomaticStop() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        link.files.disconnect()
        await watch.session.begin()

        link.watchClock.advance(VoiceRecordingSession.cap - 31)
        watch.session.tick()
        XCTAssertFalse(watch.session.isNearCap)
        link.watchClock.advance(1)
        watch.session.tick()
        XCTAssertTrue(watch.session.isNearCap)
        link.watchClock.advance(30)
        watch.session.tick()

        XCTAssertEqual(link.files.transferCalls.first?.entry.duration, VoiceRecordingSession.cap)
        guard case .saved(_, reachedCap: true)? = watch.session.outcome else {
            return XCTFail("Expected an automatic stop and save")
        }
    }

    // MARK: Shared context

    func testPublishingTheAcknowledgmentKeepsTheMemoListAndTheSyncRevisionMovingForward() async throws {
        let link = try makeLink()
        let watch = launchWatch(link)
        let phone = launchPhone(link)
        phone.addWrittenMemo(text: "Written on the phone")

        let id = try await record(watch, link)
        await settle()

        let revisions = link.snapshots.published.map(\.revision)
        XCTAssertEqual(revisions, revisions.sorted())
        XCTAssertEqual(Set(revisions).count, revisions.count, "Every publish has its own revision")
        let last = try XCTUnwrap(link.snapshots.published.last)
        XCTAssertEqual(Set(last.memos.map(\.title)), ["Written on the phone", "Voice memo"])
        XCTAssertEqual(last.acknowledgedMemoIDs, [id])
    }
}
