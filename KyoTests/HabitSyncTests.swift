import SwiftData
import XCTest

/// Habit sync (ADR 0003): a publishing phone store and a mirroring Watch store connected by a
/// controllable transport. September 2026: Sundays fall on the 6th, 13th, 20th and 27th.
@MainActor
final class HabitSyncTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        return calendar
    }()
    private var phoneNow = Date()
    private var watchNow = Date()

    private func date(_ month: Int, _ day: Int, hour: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func sep(_ day: Int, hour: Int = 10) -> Date { date(9, day, hour: hour) }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "HabitSyncTests-\(UUID().uuidString)"
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
        XCTAssertEqual(watch.habits.map(\.name), phone.habits.map(\.name), file: file, line: line)
        XCTAssertEqual(watch.habits.map(\.order), phone.habits.map(\.order), file: file, line: line)
        XCTAssertEqual(watch.habits.map(\.scheduleHistory), phone.habits.map(\.scheduleHistory), file: file, line: line)
        XCTAssertEqual(rows(watch), rows(phone), file: file, line: line)
        XCTAssertEqual(watch.doneCount, phone.doneCount, file: file, line: line)
        XCTAssertEqual(watch.todayCount, phone.todayCount, file: file, line: line)
    }

    // MARK: Convergence

    func testWatchConvergesAfterAddEditDeleteAndCheckOffOnPhone() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        assertConverged(phone, watch)

        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let read = try XCTUnwrap(phone.addHabit(name: "Read", schedule: .weeklyTarget(3)))
        let gym = try XCTUnwrap(phone.addHabit(name: "Gym", schedule: .weekdays([2, 4, 6])))
        assertConverged(phone, watch)
        XCTAssertEqual(watch.habits.count, 3)

        _ = phone.toggleCheckOff(id: walk.id)
        _ = phone.toggleCheckOff(id: read.id)
        assertConverged(phone, watch)
        XCTAssertEqual(watch.doneCount, 2)
        XCTAssertEqual(watch.todayHabits.first(where: { $0.habit.id == read.id })?.weekProgress?.count, 1)

        _ = phone.editHabit(id: gym.id, name: "Lift", schedule: .everyDay)
        assertConverged(phone, watch)
        XCTAssertEqual(watch.habits.last?.name, "Lift")

        _ = phone.toggleCheckOff(id: walk.id)   // uncheck
        assertConverged(phone, watch)
        XCTAssertEqual(watch.doneCount, 1)

        _ = phone.deleteHabit(id: read.id)
        assertConverged(phone, watch)
        XCTAssertFalse(watch.habits.contains { $0.id == read.id })
    }

    func testWatchStartedAfterPhoneChangesShowsLatestHabits() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let habit = try XCTUnwrap(phone.addHabit(name: "Walk"))
        _ = phone.toggleCheckOff(id: habit.id)

        let watch = try makeWatch(transport)
        assertConverged(phone, watch)
        XCTAssertTrue(watch.hasSynced)
    }

    func testReconnectCatchesUpOnLatestSnapshot() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)

        transport.disconnect()
        _ = phone.addHabit(name: "Walk")
        _ = phone.addHabit(name: "Read")
        XCTAssertEqual(watch.habits.count, 0)

        transport.reconnect()
        assertConverged(phone, watch)
        XCTAssertEqual(watch.habits.count, 2)
    }

    func testWatchFollowsPhoneReorderAndCannotReorderItself() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let read = try XCTUnwrap(phone.addHabit(name: "Read"))

        phone.moveHabits(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        assertConverged(phone, watch)
        XCTAssertEqual(watch.habits.map(\.id), [read.id, walk.id])

        watch.moveHabits(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(watch.habits.map(\.id), [read.id, walk.id])
        assertConverged(phone, watch)
    }

    func testWatchStoreCannotAddEditOrDeleteHabits() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let habit = try XCTUnwrap(phone.addHabit(name: "Walk"))

        XCTAssertNil(watch.addHabit(name: "Local"))
        XCTAssertNil(watch.editHabit(id: habit.id, name: "X", schedule: .everyDay))
        XCTAssertNil(watch.deleteHabit(id: habit.id))
        assertConverged(phone, watch)
    }

    // MARK: Revision rule

    func testDuplicateAndStaleSnapshotsAreIgnored() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)

        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let afterAdd = try XCTUnwrap(transport.published.last)
        _ = phone.toggleCheckOff(id: walk.id)
        _ = phone.addHabit(name: "Read")
        let latest = try XCTUnwrap(transport.published.last)

        transport.deliver(afterAdd)   // stale
        assertConverged(phone, watch)
        XCTAssertEqual(watch.habits.count, 2)
        XCTAssertEqual(watch.doneCount, 1)

        transport.deliver(latest)     // duplicate
        transport.deliver(latest)
        assertConverged(phone, watch)

        let first = try XCTUnwrap(transport.published.first)   // the store-creation publish
        transport.deliver(first)
        assertConverged(phone, watch)
    }

    func testRevisionsIncreaseStrictlyAndSurviveRestart() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let defaults = try makeDefaults()
        let container = try HabitStorage.makeContainer()
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport, defaults: defaults, container: container)
        _ = phone.addHabit(name: "Walk")
        _ = phone.addHabit(name: "Read")
        let before = transport.published.map(\.revision)
        XCTAssertEqual(before.count, 3)   // store creation, then one per change
        XCTAssertTrue(zip(before, before.dropFirst()).allSatisfy { $0 < $1 }, "\(before)")

        // Restart: republishes the persisted revision or later, never lower.
        let restarted = ControllableHabitTransport()
        _ = try makePhone(restarted, defaults: defaults, container: container)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(restarted.published.last).revision, try XCTUnwrap(before.last))
    }

    // MARK: Never synced, persistence

    func testNeverSyncedWatchReportsNotSyncedUntilFirstSnapshot() throws {
        watchNow = sep(7)
        let transport = ControllableHabitTransport()
        let watch = try makeWatch(transport)
        XCTAssertFalse(watch.hasSynced)
        XCTAssertTrue(watch.habits.isEmpty)
        XCTAssertTrue(watch.todayHabits.isEmpty)

        // A snapshot with no habits is still a sync: "No habits yet", not "Open Kyo".
        transport.deliver(HabitListSnapshot(revision: 5, habits: []))
        XCTAssertTrue(watch.hasSynced)
        XCTAssertTrue(watch.habits.isEmpty)
    }

    func testPhoneIsAlwaysSynced() throws {
        let phone = try makePhone(ControllableHabitTransport())
        XCTAssertTrue(phone.hasSynced)
    }

    func testMirrorPersistsHabitsAndRevisionAcrossRestart() throws {
        phoneNow = sep(7); watchNow = sep(7)
        let watchDefaults = try makeDefaults()
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport, defaults: watchDefaults)
        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        _ = phone.toggleCheckOff(id: walk.id)
        let expected = rows(watch)
        XCTAssertFalse(expected.isEmpty)

        // A restarted Watch with no transport traffic shows the persisted list, and still
        // rejects an older snapshot.
        let offline = ControllableHabitTransport()
        let restarted = try makeWatch(offline, defaults: watchDefaults)
        XCTAssertTrue(restarted.hasSynced)
        XCTAssertEqual(rows(restarted), expected)

        let stale = HabitListSnapshot(revision: 1, habits: [])
        offline.deliver(stale)
        XCTAssertEqual(rows(restarted), expected)

        let newer = HabitListSnapshot(revision: Int64.max, habits: [])
        offline.deliver(newer)
        XCTAssertTrue(restarted.habits.isEmpty)
    }

    // MARK: Rollover

    func testWatchRecomputesTodayPastMidnightWithoutANewSnapshot() throws {
        phoneNow = sep(1); watchNow = sep(1)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)

        let walk = try XCTUnwrap(phone.addHabit(name: "Walk"))
        let gym = try XCTUnwrap(phone.addHabit(name: "Gym", schedule: .weekdays([2])))   // Mondays
        _ = try XCTUnwrap(phone.addHabit(name: "Read", schedule: .weeklyTarget(2)))
        // Build a streak over earlier days, then check off Monday.
        for day in 1...7 {
            phoneNow = sep(day)
            phone.refreshForCurrentDay()
            _ = phone.toggleCheckOff(id: walk.id)
        }
        phoneNow = sep(7)
        phone.refreshForCurrentDay()
        _ = phone.toggleCheckOff(id: gym.id)
        let published = transport.published.count
        watchNow = sep(7)
        watch.refreshForCurrentDay()
        XCTAssertEqual(phone.todayHabits.first(where: { $0.habit.id == walk.id })?.streak, 7, "phone")
        XCTAssertEqual(watch.habits.first(where: { $0.id == walk.id })?.checkOffs.count, 7, "watch log")
        XCTAssertEqual(watch.todayHabits.first(where: { $0.habit.id == walk.id })?.streak, 7)
        XCTAssertTrue(try XCTUnwrap(watch.todayHabits.first(where: { $0.habit.id == walk.id })).isDone)

        // Past midnight, Tuesday: the Watch recomputes alone. Gym (Mondays) is off the list,
        // Walk is to-do again with its streak intact, and Read starts its week with 0/2.
        watchNow = sep(8, hour: 0)
        watch.refreshForCurrentDay()
        XCTAssertEqual(transport.published.count, published)
        XCTAssertEqual(watch.todayHabits.map(\.habit.name), ["Walk", "Read"])
        let tuesdayWalk = try XCTUnwrap(watch.todayHabits.first)
        XCTAssertFalse(tuesdayWalk.isDone)
        XCTAssertEqual(tuesdayWalk.streak, 7)
        XCTAssertEqual(watch.doneCount, 0)
        XCTAssertEqual(watch.todayCount, 2)

        // The phone, rolled over to the same instant, agrees.
        phoneNow = sep(8, hour: 0)
        phone.refreshForCurrentDay()
        XCTAssertEqual(rows(watch), rows(phone))

        // A missed day breaks the streak on the Watch, like the phone.
        watchNow = sep(9, hour: 0); phoneNow = sep(9, hour: 0)
        watch.refreshForCurrentDay(); phone.refreshForCurrentDay()
        XCTAssertEqual(watch.todayHabits.first(where: { $0.habit.id == walk.id })?.streak, 0)
        XCTAssertEqual(rows(watch), rows(phone))

        // Next week the weekly target's progress starts over on the Watch as well.
        watchNow = date(9, 14); phoneNow = date(9, 14)
        watch.refreshForCurrentDay(); phone.refreshForCurrentDay()
        XCTAssertEqual(rows(watch), rows(phone))
    }

    func testWatchRolloverAgreesWithPhoneAcrossDaysWithTrimmedLog() throws {
        phoneNow = sep(1); watchNow = sep(1)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let daily = try XCTUnwrap(phone.addHabit(name: "Daily"))
        let weekly = try XCTUnwrap(phone.addHabit(name: "Weekly", schedule: .weeklyTarget(2)))
        // Daily: checked every day but the 3rd; Weekly: checked the 8th, 10th and 15th, 17th.
        for day in 1...16 {
            phoneNow = sep(day)
            phone.refreshForCurrentDay()
            if day != 3 { _ = phone.toggleCheckOff(id: daily.id) }
            if [8, 10, 15].contains(day) { _ = phone.toggleCheckOff(id: weekly.id) }
        }
        phoneNow = sep(16); watchNow = sep(16)
        phone.refreshForCurrentDay(); watch.refreshForCurrentDay()
        // Snapshot published on the 16th's last change; the Watch's log is trimmed.
        XCTAssertLessThan(try XCTUnwrap(watch.habits.first { $0.id == daily.id }).checkOffs.count,
                          try XCTUnwrap(phone.habits.first { $0.id == daily.id }).checkOffs.count)

        for day in 17...30 {
            phoneNow = sep(day, hour: 0); watchNow = sep(day, hour: 0)
            phone.refreshForCurrentDay(); watch.refreshForCurrentDay()
            XCTAssertEqual(rows(watch), rows(phone), "day \(day)")
        }
    }

    // MARK: Trimmed log

    private func day(_ offset: Int, from today: Date) -> TaskCompletionDay {
        TaskCompletionDay(date: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
    }

    /// A deterministic generator so scenarios are reproducible.
    private struct Lcg {
        var state: UInt64
        mutating func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
    }

    private func assertTrimEquivalent(_ habit: Habit, today: Date, laterDays: Int = 10, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let trimmed = habit.trimmedLog(on: today, calendar: calendar)
        XCTAssertLessThanOrEqual(trimmed.checkOffs.count, habit.checkOffs.count, label, file: file, line: line)
        for offset in 0...laterDays {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            XCTAssertEqual(trimmed.streak(on: date, calendar: calendar), habit.streak(on: date, calendar: calendar), "\(label) streak +\(offset)", file: file, line: line)
            XCTAssertEqual(trimmed.weekProgress(on: date, calendar: calendar), habit.weekProgress(on: date, calendar: calendar), "\(label) week +\(offset)", file: file, line: line)
            XCTAssertEqual(trimmed.isDue(on: date, calendar: calendar), habit.isDue(on: date, calendar: calendar), label, file: file, line: line)
        }
        let todayDay = TaskCompletionDay(date: today, calendar: calendar)
        XCTAssertEqual(trimmed.checkOffs.contains(todayDay), habit.checkOffs.contains(todayDay), label, file: file, line: line)
    }

    func testTrimmedLogReproducesStreakAndWeekProgressAcrossManyScenarios() {
        let today = sep(16)   // a Wednesday
        let createdOffset = -150
        let schedules: [[(Int, HabitSchedule)]] = [
            [(0, .everyDay)],
            [(0, .weekdays([2, 4, 6]))],
            [(0, .weekdays([1, 7]))],
            [(0, .weeklyTarget(3))],
            [(0, .weeklyTarget(1))],
            [(0, .weeklyTarget(6))],
            [(0, .everyDay), (-40, .weekdays([2, 3, 4, 5, 6]))],
            [(0, .weekdays([2, 4])), (-70, .everyDay), (-10, .weekdays([3]))],
            [(0, .everyDay), (-60, .weeklyTarget(3))],
            [(0, .weeklyTarget(2)), (-45, .everyDay)],
            [(0, .weeklyTarget(2)), (-90, .weeklyTarget(4)), (-20, .weekdays([2, 4, 6]))],
            [(0, .everyDay), (-100, .weeklyTarget(3)), (-30, .everyDay)],
        ]
        var rng = Lcg(state: 42)
        var scenarios = 0
        for (index, history) in schedules.enumerated() {
            for density in [30, 55, 80, 95, 100] {
                for variant in 0..<3 {
                    // Schedule entries: first from the creation day, later ones `offset` days from today.
                    var entries = [HabitScheduleEntry(schedule: history[0].1, from: day(createdOffset, from: today))]
                    for (offset, schedule) in history.dropFirst() {
                        entries.append(HabitScheduleEntry(schedule: schedule, from: day(offset, from: today)))
                    }
                    var checkOffs: [TaskCompletionDay] = []
                    for offset in createdOffset...(variant == 2 ? 3 : 0) {
                        if rng.next() % 100 < density { checkOffs.append(day(offset, from: today)) }
                    }
                    if variant == 1 {
                        // A hard gap 40 days back, then a clean run.
                        checkOffs = checkOffs.filter { !(-45 ... -40).contains(daysFromToday($0, today: today)) }
                        for offset in -39...0 { checkOffs.append(day(offset, from: today)) }
                    }
                    let habit = Habit(
                        name: "H", order: 0, checkOffs: checkOffs,
                        createdOn: day(createdOffset, from: today), scheduleHistory: entries
                    )
                    assertTrimEquivalent(habit, today: today, "schedule \(index) density \(density) variant \(variant)")
                    scenarios += 1
                }
            }
        }
        XCTAssertEqual(scenarios, schedules.count * 15)
    }

    private func daysFromToday(_ checkOff: TaskCompletionDay, today: Date) -> Int {
        let date = calendar.date(from: DateComponents(era: checkOff.era, year: checkOff.year, month: checkOff.month, day: checkOff.day))!
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: date).day!
    }

    func testTrimmedLogDropsLogBeforeTheCurrentStreakAndWeek() {
        let today = sep(16)
        // A long daily habit: a gap 200 days ago, then a 150-day streak through today.
        let created = day(-400, from: today)
        let log = (-400 ... -201).map { day($0, from: today) } + (-149 ... 0).map { day($0, from: today) }
        let habit = Habit(name: "Long", order: 0, checkOffs: log, createdOn: created)
        XCTAssertEqual(habit.streak(on: today, calendar: calendar), 150)

        let trimmed = habit.trimmedLog(on: today, calendar: calendar)
        XCTAssertEqual(trimmed.checkOffs.count, 150)
        assertTrimEquivalent(habit, today: today, "long daily")

        // A weekly habit keeps its streak's weeks only; older weeks are dropped.
        // One check-off a week (target 2: unmet) for a while, then a recent run that meets it.
        let weeklyDays = ((-100 ... -50).filter { ($0 + 100) % 7 == 0 } + (-40 ... 0).filter { ($0 + 40) % 3 == 0 })
            .map { day($0, from: today) }
        let weekly = Habit(name: "W", order: 0, schedule: .weeklyTarget(2), checkOffs: weeklyDays, createdOn: day(-100, from: today))
        let weeklyTrimmed = weekly.trimmedLog(on: today, calendar: calendar)
        XCTAssertLessThan(weeklyTrimmed.checkOffs.count, weekly.checkOffs.count)
        assertTrimEquivalent(weekly, today: today, "long weekly")

        // With no streak, only this week's check-offs survive.
        let lapsed = Habit(
            name: "Lapsed", order: 0, schedule: .weeklyTarget(3),
            checkOffs: (-60 ... -30).map { day($0, from: today) } + [day(-1, from: today)],
            createdOn: day(-60, from: today)
        )
        let lapsedTrimmed = lapsed.trimmedLog(on: today, calendar: calendar)
        XCTAssertEqual(lapsedTrimmed.checkOffs, [day(-1, from: today)])
        assertTrimEquivalent(lapsed, today: today, "lapsed")
    }

    func testTrimmedSnapshotGivesWatchTheSameStreakAndWeekProgressAsPhone() throws {
        phoneNow = sep(1); watchNow = sep(1)
        let transport = ControllableHabitTransport()
        let phone = try makePhone(transport)
        let watch = try makeWatch(transport)
        let daily = try XCTUnwrap(phone.addHabit(name: "Daily"))
        let weekly = try XCTUnwrap(phone.addHabit(name: "Weekly", schedule: .weeklyTarget(3)))
        for day in 1...24 {
            phoneNow = sep(day)
            phone.refreshForCurrentDay()
            if day % 7 != 0 { _ = phone.toggleCheckOff(id: daily.id) }
            if day % 2 == 0 { _ = phone.toggleCheckOff(id: weekly.id) }
        }
        watchNow = phoneNow
        watch.refreshForCurrentDay()
        assertConverged(phone, watch)
        XCTAssertLessThan(try XCTUnwrap(watch.habits.first { $0.id == daily.id }).checkOffs.count,
                          try XCTUnwrap(phone.habits.first { $0.id == daily.id }).checkOffs.count)
    }

    // MARK: Merged context

    func testHabitSnapshotRoundTripsAndSharesTheContextWithTheTaskSnapshot() throws {
        let tasks = TaskListSnapshot(revision: 11, tasks: [DailyTask(text: "Task", creationOrder: 0)])
        let habits = HabitListSnapshot(revision: 22, habits: [Habit(name: "Walk", order: 0, createdOn: day(0, from: sep(7)))])

        var entries = ApplicationContextEntries()
        entries.set(try JSONEncoder().encode(tasks), forKey: "kyo.taskSnapshot")
        entries.set(try JSONEncoder().encode(habits), forKey: "kyo.habitSnapshot")
        // Republishing habits leaves the task snapshot intact, and the reverse.
        let newerHabits = HabitListSnapshot(revision: 23, habits: habits.habits)
        entries.set(try JSONEncoder().encode(newerHabits), forKey: "kyo.habitSnapshot")

        let context = entries.context
        XCTAssertEqual(context.count, 2)
        let taskData = try XCTUnwrap(context["kyo.taskSnapshot"] as? Data)
        let habitData = try XCTUnwrap(context["kyo.habitSnapshot"] as? Data)
        XCTAssertEqual(try JSONDecoder().decode(TaskListSnapshot.self, from: taskData), tasks)
        XCTAssertEqual(try JSONDecoder().decode(HabitListSnapshot.self, from: habitData), newerHabits)
    }
}
