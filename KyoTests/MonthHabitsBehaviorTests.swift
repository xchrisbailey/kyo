import SwiftData
import XCTest

/// What Month shows for habits, seen through the Month model with a real habit list on in-memory
/// storage. The clock moves day by day to build a log, as the streak tests do. October 2026 starts
/// on a Thursday: Mondays fall on the 5th and 12th, Tuesdays on the 6th. Weeks start on Sunday.
@MainActor
final class MonthHabitsBehaviorTests: XCTestCase {
    private let monday = 2
    private let thursday = 5
    private let friday = 6

    private let harness = MonthHarness(2026, 10, 1)
    private var habits: HabitListStore!
    private var model: MonthModel!

    override func setUp() async throws {
        try await super.setUp()
        try makeMonth()
    }

    /// Opens a habit list and a Month over it, on `container` when a test reopens earlier storage.
    private func makeMonth(container: ModelContainer? = nil) throws {
        let suiteName = "MonthHabitsBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        habits = HabitListStore(
            userDefaults: defaults, storageKey: "habits", modelContainer: try container ?? HabitStorage.makeContainer(),
            now: { self.harness.now }, calendar: harness.calendar
        )
        model = harness.makeModel(sources: [HabitMonthContent(habits: habits, calendar: harness.calendar)])
    }

    /// Moves the clock to `day` of `month` 2026, as the passing of time does.
    private func go(_ day: Int, month: Int = 10) {
        harness.setNow(harness.date(2026, month, day))
        habits.refreshForCurrentDay()
        model.refresh()
    }

    private func add(_ name: String, _ schedule: HabitSchedule = .everyDay) throws -> Habit {
        try XCTUnwrap(habits.addHabit(name: name, schedule: schedule))
    }

    /// Checks the habit off on each of the days, moving the clock to them in turn.
    private func check(_ habit: Habit, on days: [Int], month: Int = 10) {
        for day in days {
            go(day, month: month)
            _ = habits.toggleCheckOff(id: habit.id)
        }
    }

    private func cell(_ number: Int) throws -> MonthDay {
        try XCTUnwrap(model.weeks.flatMap(\.cells).compactMap(\.day).first { $0.number == number })
    }

    private func habitMark(_ number: Int) throws -> MonthMark {
        try cell(number).marks[MonthKind.allCases.firstIndex(of: .habits)!]
    }

    /// The Day summary's habit rows for `number`: the name and whether it was checked off.
    private func rows(on number: Int) throws -> [String] {
        model.select(try cell(number).date)
        let rows = model.selectedSummary.sections.first { $0.kind == .habits }?.rows ?? []
        return rows.map { "\($0.text): \($0.isChecked.map { $0 ? "checked" : "unchecked" } ?? "plain")" }
    }

    // MARK: The three states

    func testADayIsFilledWhenEveryDueHabitWasCheckedOff() throws {
        let stretch = try add("Stretch")
        let read = try add("Read")
        check(stretch, on: [2])
        check(read, on: [2])
        go(5)

        XCTAssertEqual(try habitMark(2), .filled)
    }

    func testADayIsHollowWhenOnlySomeDueHabitsWereCheckedOff() throws {
        let stretch = try add("Stretch")
        _ = try add("Read")
        check(stretch, on: [2])
        go(5)

        XCTAssertEqual(try habitMark(2), .hollow)
    }

    func testADayWithHabitsDueAndNoCheckOffsIsEmptyButListsThemUnchecked() throws {
        _ = try add("Stretch")
        _ = try add("Read")
        go(5)

        XCTAssertEqual(try habitMark(3), .empty)
        XCTAssertEqual(try rows(on: 3), ["Stretch: unchecked", "Read: unchecked"])
    }

    // MARK: Weekly targets

    func testHabitRowsReadAsCheckedOffOrNotCheckedOffToVoiceOver() throws {
        let walk = try add("Walk")
        _ = try add("Read")
        check(walk, on: [thursday])
        model.select(try cell(thursday).date)

        let rows = model.selectedSummary.sections.first { $0.kind == .habits }?.rows ?? []
        XCTAssertEqual(rows.map(\.text), ["Walk", "Read"])
        XCTAssertEqual(rows.map(\.accessibilityValue), ["Checked off", "Not checked off"])
        XCTAssertTrue(rows.allSatisfy { $0.accessibilityIdentifier.hasPrefix("month-summary-row-habit-") })
    }

    func testAWeeklyTargetCheckOffAloneFillsTheDay() throws {
        let run = try add("Run", .weeklyTarget(3))
        check(run, on: [2])
        go(5)

        XCTAssertEqual(try habitMark(2), .filled)
        XCTAssertEqual(try rows(on: 2), ["Run: checked"])
        XCTAssertEqual(try habitMark(3), .empty)
        XCTAssertEqual(try rows(on: 3), [])
    }

    func testAWeeklyTargetCheckOffBesideAMissedDueHabitLeavesTheDayHollow() throws {
        let run = try add("Run", .weeklyTarget(3))
        _ = try add("Stretch")
        check(run, on: [2])
        go(5)

        XCTAssertEqual(try habitMark(2), .hollow)
        XCTAssertEqual(try rows(on: 2), ["Run: checked", "Stretch: unchecked"])
    }

    // MARK: Schedules

    func testAPastDayIsJudgedByTheScheduleTheHabitHadThen() throws {
        let stretch = try add("Stretch")
        let gym = try add("Gym", .weekdays([thursday, friday]))
        check(stretch, on: [2])
        go(5)
        _ = habits.editHabit(id: gym.id, name: "Gym", schedule: .weekdays([monday]))

        // Friday the 2nd was a Gym day when it happened, so the missed Gym still holds it back.
        XCTAssertEqual(try habitMark(2), .hollow)
        XCTAssertEqual(try rows(on: 2), ["Stretch: checked", "Gym: unchecked"])
        // Monday the 5th is judged by the new schedule.
        XCTAssertEqual(try rows(on: 5), ["Stretch: unchecked", "Gym: unchecked"])
    }

    func testAHabitRescheduledOffADayItWasCheckedOffOnStillHasARowThere() throws {
        go(6)
        let gym = try add("Gym")
        check(gym, on: [6])
        _ = habits.editHabit(id: gym.id, name: "Gym", schedule: .weekdays([monday]))

        XCTAssertEqual(try habitMark(6), .filled)
        XCTAssertEqual(try rows(on: 6), ["Gym: checked"])
    }

    // MARK: Creation day

    func testDaysBeforeAHabitWasCreatedAreNotAffectedByIt() throws {
        let stretch = try add("Stretch")
        check(stretch, on: [2, 3])
        go(5)
        _ = try add("Read")

        XCTAssertEqual(try habitMark(2), .filled)
        XCTAssertEqual(try rows(on: 2), ["Stretch: checked"])
        // Read is due from the day it was created.
        XCTAssertEqual(try rows(on: 5), ["Stretch: unchecked", "Read: unchecked"])
    }

    func testAHabitSavedBeforeCreationDaysWereRecordedIsDueFromItsFirstCheckOff() throws {
        let container = try HabitStorage.makeContainer()
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Stretch","order":0,"schedule":{"everyDay":{}},
          "checkOffs":[{"era":1,"year":2026,"month":10,"day":2}]}]
        """
        try HabitStorage.seed(json: json, in: container)
        go(5)
        try makeMonth(container: container)

        XCTAssertEqual(try rows(on: 1), [])
        XCTAssertEqual(try habitMark(1), .empty)
        XCTAssertEqual(try habitMark(2), .filled)
        XCTAssertEqual(try rows(on: 3), ["Stretch: unchecked"])
    }

    func testAHabitSavedBeforeCreationDaysWereRecordedAndNeverCheckedOffIsDueFromTheDayItLoaded() throws {
        let container = try HabitStorage.makeContainer()
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Stretch","order":0,"schedule":{"everyDay":{}},"checkOffs":[]}]
        """
        try HabitStorage.seed(json: json, in: container)
        go(5)
        try makeMonth(container: container)

        XCTAssertEqual(try rows(on: 4), [])
        XCTAssertEqual(try rows(on: 5), ["Stretch: unchecked"])
    }

    // MARK: Deleting

    func testDeletingAHabitRemovesItsMarksAndRowsFromPastDays() throws {
        let stretch = try add("Stretch")
        check(stretch, on: [2])
        go(5)
        XCTAssertEqual(try habitMark(2), .filled)

        _ = habits.deleteHabit(id: stretch.id)

        XCTAssertEqual(try habitMark(2), .empty)
        XCTAssertEqual(try rows(on: 2), [])
    }

    // MARK: Recomputing

    func testCheckingOffAndUncheckingOnTodayUpdatesTodaysMarkAndRows() throws {
        go(6)
        let stretch = try add("Stretch")
        XCTAssertEqual(try habitMark(6), .empty)
        XCTAssertEqual(try rows(on: 6), ["Stretch: unchecked"])

        _ = habits.toggleCheckOff(id: stretch.id)
        XCTAssertEqual(try habitMark(6), .filled)
        XCTAssertEqual(try rows(on: 6), ["Stretch: checked"])

        _ = habits.toggleCheckOff(id: stretch.id)
        XCTAssertEqual(try habitMark(6), .empty)
        XCTAssertEqual(try rows(on: 6), ["Stretch: unchecked"])
    }

    // MARK: Other months and future days

    func testAnotherMonthsHabitMarksAndRowsAreRightAsSoonAsItIsShown() throws {
        go(28, month: 9)
        let stretch = try add("Stretch")
        let read = try add("Read")
        check(stretch, on: [28, 29], month: 9)
        check(read, on: [28], month: 9)
        go(6)

        model.showPreviousMonth()

        XCTAssertEqual(try habitMark(28), .filled)
        XCTAssertEqual(try habitMark(29), .hollow)
        XCTAssertEqual(try rows(on: 29), ["Stretch: checked", "Read: unchecked"])
        XCTAssertEqual(try habitMark(27), .empty)
        XCTAssertEqual(try rows(on: 27), [])
    }

    func testFutureDaysShowNoHabitMarkAndNoHabitRows() throws {
        let stretch = try add("Stretch")
        check(stretch, on: [2])
        go(5)

        XCTAssertEqual(try habitMark(8), .empty)
        XCTAssertEqual(try rows(on: 8), [])
        XCTAssertEqual(try cell(8).accessibilityLabel, "Thursday, October 8")
    }

    // MARK: VoiceOver

    func testADayCellSaysWhetherAllOrSomeHabitsWereDone() throws {
        let stretch = try add("Stretch")
        let read = try add("Read")
        check(stretch, on: [2, 3])
        check(read, on: [2])
        go(5)

        XCTAssertEqual(try cell(2).accessibilityLabel, "Friday, October 2, all habits done")
        XCTAssertEqual(try cell(3).accessibilityLabel, "Saturday, October 3, some habits done")
        XCTAssertEqual(try cell(4).accessibilityLabel, "Sunday, October 4")
    }
}
