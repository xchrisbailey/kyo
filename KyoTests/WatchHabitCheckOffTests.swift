import SwiftData
import XCTest

/// Watch habit check-off (#41, ADR 0003 on top of ADR 0002): a publishing phone store and a
/// mirroring Watch store connected by a controllable transport. September 2026: the 7th is a
/// Monday and Sundays fall on the 6th, 13th, 20th and 27th.
@MainActor
final class WatchHabitCheckOffTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        return calendar
    }()
    private var phoneNow = Date()
    private var watchNow = Date()

    private func sep(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func completionDay(_ day: Int) -> TaskCompletionDay {
        TaskCompletionDay(date: sep(day), calendar: calendar)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WatchHabitCheckOffTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func makePhone(
        _ transport: ControllableHabitTransport, defaults: UserDefaults? = nil, container: ModelContainer? = nil
    ) throws -> HabitListStore {
        HabitListStore(
            userDefaults: try defaults ?? makeDefaults(), storageKey: "habits",
            modelContainer: try container ?? HabitStorage.makeContainer(),
            now: { self.phoneNow }, calendar: calendar, sync: .publish(to: transport)
        )
    }

    private func makeWatch(_ transport: ControllableHabitTransport, defaults: UserDefaults? = nil) throws -> HabitListStore {
        HabitListStore(
            userDefaults: try defaults ?? makeDefaults(), storageKey: "habits",
            now: { self.watchNow }, calendar: calendar, sync: .mirror(from: transport)
        )
    }

    /// What a row shows: everything the Watch UI reads from Today's list.
    private func rows(_ store: HabitListStore) -> [[String]] {
        store.todayHabits.map { entry in
            [
                entry.habit.name, "\(entry.isDone)", "\(entry.isCheckedOffToday)", "\(entry.streak)",
                entry.weekProgress.map { "\($0.count)/\($0.target)" } ?? "-",
            ]
        }
    }

    private func assertConverged(_ phone: HabitListStore, _ watch: HabitListStore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(watch.habits.map(\.id), phone.habits.map(\.id), file: file, line: line)
        XCTAssertEqual(watch.habits.map(\.scheduleHistory), phone.habits.map(\.scheduleHistory), file: file, line: line)
        XCTAssertEqual(rows(watch), rows(phone), file: file, line: line)
        XCTAssertEqual(watch.doneCount, phone.doneCount, file: file, line: line)
        XCTAssertEqual(watch.todayCount, phone.todayCount, file: file, line: line)
    }

    /// How many commands a Watch started fresh against `defaults` would resend: the size of
    /// its persisted outbox.
    private func unacknowledgedCommandCount(defaults: UserDefaults) throws -> Int {
        let probe = ControllableHabitTransport()
        _ = try makeWatch(probe, defaults: defaults)
        return probe.sentCommands.count
    }

    private func checkOffs(_ store: HabitListStore, _ habit: Habit) throws -> [TaskCompletionDay] {
        try XCTUnwrap(store.habits.first { $0.id == habit.id }).checkOffs
    }

    // MARK: Convergence

    func testWatchCheckOffAndUncheckConvergeOnBothDevices() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let read = try XCTUnwrap(phone.addHabit(name: "Read", schedule: .weeklyTarget(3)))

        let checked = try XCTUnwrap(watch.toggleCheckOff(id: walk.id))
        XCTAssertEqual(checked.checkOffs, [completionDay(7)])
        _ = watch.toggleCheckOff(id: read.id)
        assertConverged(phone, watch)
        XCTAssertEqual(phone.doneCount, 2)   // both are checked off today
        XCTAssertEqual(try checkOffs(phone, walk), [completionDay(7)])
        XCTAssertEqual(phone.todayHabits.first { $0.habit.id == walk.id }?.streak, 1)
        XCTAssertEqual(phone.todayHabits.first { $0.habit.id == read.id }?.weekProgress?.count, 1)

        let unchecked = try XCTUnwrap(watch.toggleCheckOff(id: walk.id))
        XCTAssertEqual(unchecked.checkOffs, [])
        assertConverged(phone, watch)
        XCTAssertEqual(try checkOffs(phone, walk), [])
        XCTAssertEqual(phone.doneCount, 1)   // Read remains
    }

    func testWatchCheckOffUpdatesThePhonesHabitEntriesRightAway() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let read = try XCTUnwrap(phone.addHabit(name: "Read", schedule: .weeklyTarget(3)))

        _ = watch.toggleCheckOff(id: walk.id)
        _ = watch.toggleCheckOff(id: read.id)

        let walkEntry = try XCTUnwrap(phone.habitEntries.first { $0.id == walk.id })
        XCTAssertEqual(walkEntry.streak, 1)
        let readEntry = try XCTUnwrap(phone.habitEntries.first { $0.id == read.id })
        XCTAssertEqual(readEntry.weekProgress, HabitWeekProgress(count: 1, target: 3))

        _ = watch.toggleCheckOff(id: walk.id)
        XCTAssertEqual(phone.habitEntries.first { $0.id == walk.id }?.streak, 0)
    }

    func testWatchCheckOffShowsImmediatelyBeforeThePhoneAcknowledgesIt() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let watchDefaults = try makeDefaults()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport, defaults: watchDefaults)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let read = try XCTUnwrap(phone.addHabit(name: "Read", schedule: .weeklyTarget(2)))

        transport.disconnect()
        _ = watch.toggleCheckOff(id: walk.id)
        _ = watch.toggleCheckOff(id: read.id)

        // The Watch moves the rows to the done group and shows streak and week progress now.
        XCTAssertEqual(rows(watch), [["Walk", "true", "true", "1", "-"], ["Read", "true", "true", "0", "1/2"]])
        XCTAssertEqual(watch.doneCount, 2)
        // The phone has heard nothing yet.
        XCTAssertEqual(phone.doneCount, 0)
        XCTAssertEqual(try checkOffs(phone, walk), [])

        transport.reconnect()
        assertConverged(phone, watch)
        XCTAssertEqual(try checkOffs(phone, walk), [completionDay(7)])
        XCTAssertEqual(try unacknowledgedCommandCount(defaults: watchDefaults), 0)
    }

    func testMetButUncheckedWeeklyHabitCanStillBeCheckedOffFromTheWatch() throws {
        phoneNow = sep(9); watchNow = sep(9)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let read = try XCTUnwrap(phone.addHabit(name: "Read", schedule: .weeklyTarget(1)))
        // Met earlier in the week (Monday), so it's in the done group with an empty circle.
        phoneNow = sep(7)
        phone.refreshForCurrentDay()
        _ = phone.toggleCheckOff(id: read.id)
        phoneNow = sep(9); watchNow = sep(9)
        phone.refreshForCurrentDay(); watch.refreshForCurrentDay()
        XCTAssertEqual(rows(watch), [["Read", "true", "false", "1", "1/1"]])

        _ = watch.toggleCheckOff(id: read.id)
        assertConverged(phone, watch)
        XCTAssertEqual(rows(watch), [["Read", "true", "true", "1", "2/1"]])
        XCTAssertEqual(try checkOffs(phone, read), [completionDay(7), completionDay(9)])
    }

    // MARK: Validation

    func testWatchCanOnlyToggleHabitsOnTodaysList() throws {
        phoneNow = sep(7); watchNow = sep(7)   // a Monday
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let tuesdays = try XCTUnwrap(phone.addHabit(name: "Tuesdays", schedule: .weekdays([3])))
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        XCTAssertEqual(watch.todayHabits.map(\.habit.name), ["Walk"])

        XCTAssertNil(watch.toggleCheckOff(id: tuesdays.id))
        XCTAssertNil(watch.toggleCheckOff(id: UUID()))
        XCTAssertTrue(transport.sentCommands.isEmpty)

        // Checked off today, then made not due by a phone edit: it stays on the list and can
        // still be unchecked from the Watch.
        _ = watch.toggleCheckOff(id: walk.id)
        _ = phone.editHabit(id: walk.id, name: "Walk", schedule: .weekdays([3]))
        XCTAssertEqual(watch.todayHabits.map(\.habit.name), ["Walk"])
        let unchecked = try XCTUnwrap(watch.toggleCheckOff(id: walk.id))
        XCTAssertEqual(unchecked.checkOffs, [])
        XCTAssertTrue(watch.todayHabits.isEmpty)
        assertConverged(phone, watch)
    }

    func testWatchStoreStillCannotAddEditOrDeleteHabits() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))

        XCTAssertNil(watch.addHabit(name: "Local"))
        XCTAssertNil(watch.editHabit(id: walk.id, name: "X", schedule: .everyDay))
        XCTAssertNil(watch.deleteHabit(id: walk.id))
        XCTAssertTrue(transport.sentCommands.isEmpty)
        assertConverged(phone, watch)
    }

    // MARK: Duplicate and late delivery

    func testDuplicateDeliveryIsAppliedOnce() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))

        _ = watch.toggleCheckOff(id: walk.id)   // check
        _ = watch.toggleCheckOff(id: walk.id)   // uncheck
        let check = try XCTUnwrap(transport.sentCommands.first)
        let published = transport.published.count

        // A stale duplicate of the first command must not re-check the habit.
        transport.redeliver(check)
        transport.redeliver(check)
        XCTAssertEqual(try checkOffs(phone, walk), [])
        XCTAssertEqual(transport.published.count, published)
        assertConverged(phone, watch)

        // Duplicate delivery of a check-off applies it exactly once.
        _ = watch.toggleCheckOff(id: walk.id)
        let again = try XCTUnwrap(transport.sentCommands.last)
        transport.redeliver(again)
        XCTAssertEqual(try checkOffs(phone, walk), [completionDay(7)])
        assertConverged(phone, watch)
    }

    func testLateCheckOffForYesterdayIsRecordedOnItsOwnDay() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))

        transport.disconnect()
        watchNow = sep(7, hour: 23)
        _ = watch.toggleCheckOff(id: walk.id)

        // The command reaches the phone after midnight.
        phoneNow = sep(8); watchNow = sep(8)
        phone.refreshForCurrentDay(); watch.refreshForCurrentDay()
        transport.reconnect()

        XCTAssertEqual(try checkOffs(phone, walk), [completionDay(7)])
        // Yesterday's check-off counts toward the streak; today is still open.
        XCTAssertEqual(rows(phone), [["Walk", "false", "false", "1", "-"]])
        assertConverged(phone, watch)
    }

    // MARK: Deleted habits

    func testCheckOffForADeletedHabitIsIgnoredButAcknowledged() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let watchDefaults = try makeDefaults()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport, defaults: watchDefaults)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let read = try XCTUnwrap(phone.addHabit(name: "Read"))

        transport.disconnect()
        _ = watch.toggleCheckOff(id: walk.id)
        _ = phone.deleteHabit(id: walk.id)
        transport.reconnect()

        let command = try XCTUnwrap(transport.sentCommands.first)
        XCTAssertEqual(phone.habits.map(\.id), [read.id])
        XCTAssertEqual(try XCTUnwrap(transport.published.last).acknowledgedCommandIDs, [command.id])
        // The Watch retired the command and drops the habit with the new snapshot.
        XCTAssertEqual(watch.habits.map(\.id), [read.id])
        XCTAssertEqual(try unacknowledgedCommandCount(defaults: watchDefaults), 0)
        assertConverged(phone, watch)

        // A duplicate can't bring the habit back.
        transport.redeliver(command)
        XCTAssertEqual(phone.habits.map(\.id), [read.id])
    }

    func testCheckOffForAnUnknownHabitIsAcknowledgedAndCreatesNothing() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        _ = phone.addHabit(name: "Walk")

        let stray = HabitCommand(id: UUID(), action: .setCheckOff(habitID: UUID(), day: completionDay(7), isCheckedOff: true))
        transport.send(stray)

        XCTAssertEqual(phone.habits.map(\.name), ["Walk"])
        XCTAssertEqual(try checkOffs(phone, try XCTUnwrap(phone.habits.first)), [])
        XCTAssertEqual(try XCTUnwrap(transport.published.last).acknowledgedCommandIDs, [stray.id])
        assertConverged(phone, watch)
    }

    func testDeleteRacingAnOfflineCheckOffLeavesNoTraceOnEitherDevice() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let watchDefaults = try makeDefaults()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport, defaults: watchDefaults)

        // The phone adds and the Watch learns the habit; then the Watch checks it off while the
        // phone deletes it, and the Watch restarts before reconnecting.
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        transport.disconnect()
        _ = watch.toggleCheckOff(id: walk.id)
        _ = phone.deleteHabit(id: walk.id)
        let restarted = try makeWatch(transport, defaults: watchDefaults)
        XCTAssertEqual(restarted.todayHabits.map(\.habit.name), ["Walk"])   // still the old snapshot, plus the tap
        transport.reconnect()

        XCTAssertTrue(phone.habits.isEmpty)
        XCTAssertTrue(restarted.habits.isEmpty)
        XCTAssertTrue(restarted.todayHabits.isEmpty)
        XCTAssertEqual(try unacknowledgedCommandCount(defaults: watchDefaults), 0)
    }

    func testTombstonesSurvivePhoneRestart() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phoneDefaults = try makeDefaults()
        let phoneContainer = try HabitStorage.makeContainer()
        let phone = try makePhone(transport, defaults: phoneDefaults, container: phoneContainer)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let savedWithHabit = phone.habits
        _ = phone.deleteHabit(id: walk.id)

        // Simulate stale habit data coming back (e.g. restored from an old save) behind a
        // restart: the persisted tombstone still protects the deleted habit.
        HabitStorage.seed(savedWithHabit, in: phoneContainer)
        let restartedTransport = ControllableHabitTransport()
        let restarted = try makePhone(restartedTransport, defaults: phoneDefaults, container: phoneContainer)
        XCTAssertEqual(restarted.habits.map(\.id), [walk.id])

        let command = HabitCommand(id: UUID(), action: .setCheckOff(habitID: walk.id, day: completionDay(7), isCheckedOff: true))
        restartedTransport.send(command)

        XCTAssertEqual(try checkOffs(restarted, walk), [])
        XCTAssertEqual(try XCTUnwrap(restartedTransport.published.last).acknowledgedCommandIDs, [command.id])
    }

    // MARK: Schedule edits

    func testCheckOffArrivingAfterAScheduleEditStillCountsOnTheDayItsScheduleMadeItDue() throws {
        phoneNow = sep(7); watchNow = sep(7)   // Monday
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let gym = try XCTUnwrap(phone.addHabit(name: "Gym", schedule: .weekdays([2])))   // Mondays

        transport.disconnect()
        _ = watch.toggleCheckOff(id: gym.id)
        // On Tuesday the phone edits the schedule to Tuesdays, then the command arrives.
        phoneNow = sep(8); watchNow = sep(8)
        phone.refreshForCurrentDay(); watch.refreshForCurrentDay()
        _ = phone.editHabit(id: gym.id, name: "Gym", schedule: .weekdays([3]))
        transport.reconnect()

        XCTAssertEqual(try checkOffs(phone, gym), [completionDay(7)])
        // Monday was due under the schedule it had, so it counts; Tuesday is open.
        XCTAssertEqual(rows(phone), [["Gym", "false", "false", "1", "-"]])
        assertConverged(phone, watch)
    }

    func testCheckOffArrivingAfterAnEditThatMadeThatDayNotDueIsRecordedButDoesNotCount() throws {
        phoneNow = sep(7); watchNow = sep(7)   // Monday
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))

        transport.disconnect()
        _ = watch.toggleCheckOff(id: walk.id)
        // The same day, the phone makes it Tuesday-only before the command arrives.
        _ = phone.editHabit(id: walk.id, name: "Walk", schedule: .weekdays([3]))
        transport.reconnect()

        XCTAssertEqual(try checkOffs(phone, walk), [completionDay(7)])
        // It stays on Today with its check-off, which doesn't count toward the streak.
        XCTAssertEqual(rows(phone), [["Walk", "true", "true", "0", "-"]])
        assertConverged(phone, watch)
    }

    // MARK: Outbox, acknowledgment, restart

    func testAcknowledgmentRetiresTheOutboxEvenFromAStaleSnapshot() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let watchDefaults = try makeDefaults()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport, defaults: watchDefaults)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))

        transport.disconnect()
        _ = watch.toggleCheckOff(id: walk.id)
        let command = try XCTUnwrap(transport.sentCommands.first)
        XCTAssertEqual(try unacknowledgedCommandCount(defaults: watchDefaults), 1)

        // A snapshot older than what the Watch has applied can't replace its habits, but the
        // acknowledgment still retires the command.
        transport.deliver(HabitListSnapshot(revision: 1, habits: [], acknowledgedCommandIDs: [command.id]))
        XCTAssertEqual(try unacknowledgedCommandCount(defaults: watchDefaults), 0)
        XCTAssertEqual(watch.habits.map(\.id), [walk.id])
        XCTAssertEqual(rows(watch), [["Walk", "false", "false", "0", "-"]])   // no longer replayed
    }

    func testUnacknowledgedCheckOffsAreResentWhenTheWatchRestarts() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let watchDefaults = try makeDefaults()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport, defaults: watchDefaults)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let read = try XCTUnwrap(phone.addHabit(name: "Read"))

        transport.disconnect()
        _ = watch.toggleCheckOff(id: walk.id)
        _ = watch.toggleCheckOff(id: read.id)
        XCTAssertEqual(transport.sentCommands.count, 2)

        // Restart: the outbox survives, still shows on the Watch, and is resent in order.
        let restarted = try makeWatch(transport, defaults: watchDefaults)
        XCTAssertEqual(restarted.doneCount, 2)
        XCTAssertEqual(transport.sentCommands.count, 4)
        XCTAssertEqual(Array(transport.sentCommands.suffix(2)), Array(transport.sentCommands.prefix(2)))

        transport.reconnect()
        // The phone applied each command once despite the duplicates, and both devices agree.
        XCTAssertEqual(try checkOffs(phone, walk), [completionDay(7)])
        XCTAssertEqual(try checkOffs(phone, read), [completionDay(7)])
        assertConverged(phone, restarted)
        XCTAssertEqual(try unacknowledgedCommandCount(defaults: watchDefaults), 0)
    }

    func testWatchBaseAndOutboxSurviveRestartAndKeepRejectingOlderSnapshots() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let watchDefaults = try makeDefaults()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport, defaults: watchDefaults)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        _ = phone.addHabit(name: "Read")

        transport.disconnect()
        _ = watch.toggleCheckOff(id: walk.id)
        let expected = rows(watch)

        let offline = ControllableHabitTransport()
        let restarted = try makeWatch(offline, defaults: watchDefaults)
        XCTAssertTrue(restarted.hasSynced)
        XCTAssertEqual(rows(restarted), expected)
        offline.deliver(HabitListSnapshot(revision: 1, habits: []))
        XCTAssertEqual(rows(restarted), expected)
    }

    // MARK: Phone persistence and bounds

    func testProcessedCommandsSurvivePhoneRestart() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phoneDefaults = try makeDefaults()
        let phoneContainer = try HabitStorage.makeContainer()
        let phone = try makePhone(transport, defaults: phoneDefaults, container: phoneContainer)
        let watch = try makeWatch(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))

        _ = watch.toggleCheckOff(id: walk.id)   // check
        _ = watch.toggleCheckOff(id: walk.id)   // uncheck
        let check = try XCTUnwrap(transport.sentCommands.first)
        let uncheck = try XCTUnwrap(transport.sentCommands.last)

        let restartedTransport = ControllableHabitTransport()
        let restarted = try makePhone(restartedTransport, defaults: phoneDefaults, container: phoneContainer)
        // Republished on creation with the acknowledgments intact.
        XCTAssertEqual(Set(try XCTUnwrap(restartedTransport.published.last).acknowledgedCommandIDs), [check.id, uncheck.id])

        restartedTransport.send(check)   // a stale duplicate after the restart
        XCTAssertEqual(try checkOffs(restarted, walk), [])
        XCTAssertEqual(restartedTransport.published.count, 1)
    }

    func testProcessedCommandSetKeepsTheMostRecentFiveHundred() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))

        func command(_ day: Int, _ isCheckedOff: Bool) -> HabitCommand {
            HabitCommand(id: UUID(), action: .setCheckOff(habitID: walk.id, day: completionDay(day), isCheckedOff: isCheckedOff))
        }
        let first = command(7, true)
        let second = command(7, false)
        transport.send(first)
        transport.send(second)
        for index in 0..<499 {
            transport.send(command(1 + index % 5, index % 2 == 0))
        }
        // 501 commands processed: the oldest is no longer remembered, the rest are.
        let acknowledged = try XCTUnwrap(transport.published.last).acknowledgedCommandIDs
        XCTAssertEqual(acknowledged.count, 500)
        XCTAssertFalse(acknowledged.contains(first.id))
        XCTAssertTrue(acknowledged.contains(second.id))

        XCTAssertFalse(try checkOffs(phone, walk).contains(completionDay(7)))
        transport.redeliver(second)   // still remembered: ignored
        XCTAssertFalse(try checkOffs(phone, walk).contains(completionDay(7)))
        transport.redeliver(first)    // forgotten: applied again
        XCTAssertTrue(try checkOffs(phone, walk).contains(completionDay(7)))
    }

    // MARK: Wire format

    func testSnapshotWithoutAcknowledgmentsDecodesAsEmpty() throws {
        let snapshot = HabitListSnapshot(revision: 9, habits: [Habit(name: "Walk", order: 0, createdOn: completionDay(7))])
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object["acknowledgedCommandIDs"])
        object["acknowledgedCommandIDs"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HabitListSnapshot.self, from: legacy)
        XCTAssertEqual(decoded.acknowledgedCommandIDs, [])
        XCTAssertEqual(decoded.habits, snapshot.habits)
    }

    func testCheckOffCommandRoundTrips() throws {
        let command = HabitCommand(id: UUID(), action: .setCheckOff(habitID: UUID(), day: completionDay(7), isCheckedOff: true))
        let decoded = try JSONDecoder().decode(HabitCommand.self, from: try JSONEncoder().encode(command))
        XCTAssertEqual(decoded, command)
    }
}
