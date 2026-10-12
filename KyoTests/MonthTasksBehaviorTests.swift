import XCTest

/// Tasks completed in Month, driven through the Month model with a real task list on in-memory
/// storage. Today is Tuesday 6 October 2026 unless a test moves the clock.
@MainActor
final class MonthTasksBehaviorTests: MonthTestCase {
    private let harness = MonthHarness(2026, 10, 6)

    private func makeTaskList() throws -> TaskListStore {
        TaskListStore(
            modelContainer: try KyoModelContainer.make(inMemory: true),
            now: { self.harness.now },
            calendar: harness.calendar
        )
    }

    private func makeModel(_ taskList: TaskListStore) -> MonthModel {
        harness.makeModel(sources: [TaskMonthContent(taskList: taskList)])
    }

    private func taskMark(_ number: Int, in model: MonthModel) throws -> MonthMark {
        try day(number, in: model).marks[1]
    }

    /// Adds a task and completes it with the clock at `moment`, then returns the clock to where it was.
    @discardableResult
    private func completeTask(_ text: String, in taskList: TaskListStore, on moment: Date) throws -> DailyTask {
        let resume = harness.now
        harness.setNow(moment)
        defer { harness.setNow(resume) }
        let task = try XCTUnwrap(taskList.addTask(text: text))
        return try XCTUnwrap(taskList.toggleTask(id: task.id))
    }

    private func taskRows(in model: MonthModel) -> [String] {
        model.selectedSummary.sections.first { $0.kind == .tasks }?.rows.map(\.text) ?? []
    }

    func testFuturePlannedTasksHaveHollowMarksPlannedCountsAndReadOnlyRows() throws {
        let list = try makeTaskList()
        let task = try XCTUnwrap(list.addTask(text: "Call Friday"))
        _ = list.deferTask(id: task.id, to: harness.date(2026, 10, 9))
        let model = makeModel(list)
        XCTAssertEqual(try taskMark(9, in: model), .hollow)
        XCTAssertEqual(try day(9, in: model).accessibilityLabel, "Friday, October 9, 1 task planned")
        model.select(harness.date(2026, 10, 9, hour: 0))
        let rows = model.selectedSummary.sections.first { $0.kind == .tasks }?.rows ?? []
        XCTAssertEqual(rows.map(\.text), ["Call Friday"])
        XCTAssertEqual(rows.map(\.accessibilityValue), ["Planned"])
        XCTAssertEqual(rows.first?.kind, .task(isComplete: false))
        XCTAssertNil(rows.first?.target)
    }

    func testMixedDayDistinguishesPlannedAndCompletedCountsAndRows() throws {
        let list = try makeTaskList()
        let planned = try XCTUnwrap(list.addTask(text: "Planned today"))
        _ = list.deferTask(id: planned.id, to: harness.date(2026, 10, 6))
        _ = try completeTask("Finished today", in: list, on: harness.date(2026, 10, 6))
        let model = makeModel(list)
        XCTAssertEqual(try taskMark(6, in: model), .mixed)
        XCTAssertEqual(try day(6, in: model).accessibilityLabel,
                       "Tuesday, October 6, Today, 1 task planned, 1 task completed")
        let rows = model.selectedSummary.sections.first { $0.kind == .tasks }?.rows ?? []
        XCTAssertEqual(rows.map(\.accessibilityValue), ["Planned", "Completed"])
        XCTAssertTrue(rows.allSatisfy { $0.target == nil })
    }

    func testReschedulingRenamingBringingToTodayAndDeletingRefreshPlannedRowsImmediately() throws {
        let list = try makeTaskList()
        let task = try XCTUnwrap(list.addTask(text: "Original"))
        let model = makeModel(list)
        _ = list.deferTask(id: task.id, to: harness.date(2026, 10, 9))
        XCTAssertEqual(try taskMark(9, in: model), .hollow)
        _ = list.deferTask(id: task.id, to: harness.date(2026, 10, 10))
        XCTAssertEqual(try taskMark(9, in: model), .empty)
        model.select(harness.date(2026, 10, 10, hour: 0))
        _ = list.editTask(id: task.id, text: "Renamed")
        XCTAssertEqual(taskRows(in: model), ["Renamed"])
        _ = list.bringTaskToToday(id: task.id)
        XCTAssertEqual(try taskMark(10, in: model), .empty)
        XCTAssertTrue(taskRows(in: model).isEmpty)
        _ = list.deferTask(id: task.id, to: harness.date(2026, 10, 10))
        _ = list.deleteTask(id: task.id)
        XCTAssertEqual(try taskMark(10, in: model), .empty)
        XCTAssertTrue(taskRows(in: model).isEmpty)
    }

    func testCompletionOnADifferentDayReplacesPlannedRowWithActualCompletionHistory() throws {
        let list = try makeTaskList()
        let task = try XCTUnwrap(list.addTask(text: "Friday work"))
        _ = list.deferTask(id: task.id, to: harness.date(2026, 10, 9))
        let model = makeModel(list)
        harness.setNow(harness.date(2026, 10, 10))
        list.refreshForCurrentDay()
        _ = list.toggleTask(id: task.id)
        model.select(harness.date(2026, 10, 9, hour: 0))
        XCTAssertEqual(try taskMark(9, in: model), .empty)
        XCTAssertTrue(taskRows(in: model).isEmpty)
        model.select(harness.date(2026, 10, 10, hour: 0))
        XCTAssertEqual(try taskMark(10, in: model), .filled)
        XCTAssertEqual(taskRows(in: model), ["Friday work"])
        XCTAssertEqual(model.selectedSummary.sections.first?.rows.first?.accessibilityValue, "Completed")
    }

    func testCompletionOnPlannedDayHasOneCompletedRowAndNoDuplicatePlannedRow() throws {
        let list = try makeTaskList()
        let task = try XCTUnwrap(list.addTask(text: "Today work"))
        _ = list.deferTask(id: task.id, to: harness.date(2026, 10, 6))
        let model = makeModel(list)
        _ = list.toggleTask(id: task.id)
        XCTAssertEqual(taskRows(in: model), ["Today work"])
        XCTAssertEqual(try taskMark(6, in: model), .filled)
        XCTAssertEqual(try day(6, in: model).accessibilityLabel, "Tuesday, October 6, Today, 1 task completed")
    }

    func testFutureDayWithPlannedWorkSuppressesRecordedFutureCompletions() throws {
        let list = try makeTaskList()
        let task = try XCTUnwrap(list.addTask(text: "Planned"))
        _ = list.deferTask(id: task.id, to: harness.date(2026, 10, 9))
        _ = try completeTask("Future completion", in: list, on: harness.date(2026, 10, 9))
        let model = makeModel(list)
        model.select(harness.date(2026, 10, 9, hour: 0))
        XCTAssertEqual(taskRows(in: model), ["Planned"])
        XCTAssertEqual(try taskMark(9, in: model), .hollow)
        XCTAssertEqual(try day(9, in: model).accessibilityLabel, "Friday, October 9, 1 task planned")
        harness.setNow(harness.date(2026, 10, 9))
        model.refresh()
        XCTAssertEqual(taskRows(in: model), ["Planned", "Future completion"])
        XCTAssertEqual(try taskMark(9, in: model), .mixed)
    }

    func testNextMonthShowsFuturePlannedTasks() throws {
        let list = try makeTaskList()
        let task = try XCTUnwrap(list.addTask(text: "November"))
        _ = list.deferTask(id: task.id, to: harness.date(2026, 11, 1))
        let model = makeModel(list)
        model.showNextMonth()
        XCTAssertEqual(try taskMark(1, in: model), .hollow)
        XCTAssertEqual(taskRows(in: model), ["November"])
    }

    func testLiveTimeZoneChangePreservesShownMonthSelectedCivilDayAndPlannedRow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z"))
        let list = TaskListStore(modelContainer: try KyoModelContainer.make(inMemory: true), now: { now },
                                 calendarProvider: { calendar })
        let task = try XCTUnwrap(list.addTask(text: "Fixed Friday"))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9)))
        _ = list.deferTask(id: task.id, to: friday)
        let model = MonthModel(now: { now }, calendarProvider: { calendar }, locale: Locale(identifier: "en_US"),
                               sources: [TaskMonthContent(taskList: list)])
        model.select(friday)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Detroit"))
        list.refreshForCurrentDay()
        model.refresh()
        XCTAssertEqual(model.headerText, "October 2026")
        XCTAssertEqual(model.selectedDay, ISO8601DateFormatter().date(from: "2026-10-09T04:00:00Z"))
        XCTAssertEqual(taskRows(in: model), ["Fixed Friday"])
        XCTAssertEqual(try taskMark(9, in: model), .hollow)
        XCTAssertEqual(try taskMark(8, in: model), .empty)
    }

    // MARK: Marks

    func testADayWithACompletedTaskShowsTheTaskMarkAndNoOtherDayDoes() throws {
        let taskList = try makeTaskList()
        try completeTask("Pay rent", in: taskList, on: harness.date(2026, 10, 3))
        let model = makeModel(taskList)

        XCTAssertEqual(try taskMark(3, in: model), .filled)
        XCTAssertEqual(try taskMark(2, in: model), .empty)
        XCTAssertEqual(try taskMark(4, in: model), .empty)
        XCTAssertEqual(try day(3, in: model).marks, [.empty, .filled, .empty, .empty])
    }

    func testUnscheduledOpenTasksNeverMarkADay() throws {
        let taskList = try makeTaskList()
        taskList.addTask(text: "Not yet")
        let model = makeModel(taskList)

        XCTAssertEqual(try taskMark(6, in: model), .empty)
        XCTAssertTrue(taskRows(in: model).isEmpty)
    }

    func testTodayFollowsTheSameRuleAsAnyOtherDay() throws {
        let taskList = try makeTaskList()
        let open = try XCTUnwrap(taskList.addTask(text: "Still open"))
        try completeTask("Done today", in: taskList, on: harness.date(2026, 10, 6))
        let model = makeModel(taskList)

        XCTAssertEqual(try taskMark(6, in: model), .filled)
        XCTAssertEqual(taskRows(in: model), ["Done today"])
        XCTAssertFalse(taskRows(in: model).contains(open.text))
    }

    func testTheDayCellReadsTheCountOfTasksCompleted() throws {
        let taskList = try makeTaskList()
        try completeTask("One", in: taskList, on: harness.date(2026, 10, 3))
        try completeTask("Two", in: taskList, on: harness.date(2026, 10, 3))
        try completeTask("Three", in: taskList, on: harness.date(2026, 10, 3))
        try completeTask("Solo", in: taskList, on: harness.date(2026, 10, 4))
        let model = makeModel(taskList)

        XCTAssertEqual(try day(3, in: model).accessibilityLabel, "Saturday, October 3, 3 tasks completed")
        XCTAssertEqual(try day(4, in: model).accessibilityLabel, "Sunday, October 4, 1 task completed")
    }

    // MARK: Day summary

    func testTheDaySummaryListsTheTasksCompletedOnTheSelectedDayAndNothingElse() throws {
        let taskList = try makeTaskList()
        try completeTask("Pay rent", in: taskList, on: harness.date(2026, 10, 3))
        try completeTask("Call Sam", in: taskList, on: harness.date(2026, 10, 3))
        try completeTask("Water plants", in: taskList, on: harness.date(2026, 10, 4))
        let model = makeModel(taskList)

        model.select(harness.date(2026, 10, 3, hour: 0))
        XCTAssertEqual(taskRows(in: model), ["Pay rent", "Call Sam"])
        XCTAssertFalse(model.selectedSummary.isEmpty, "a day with completed tasks isn't empty")

        model.select(harness.date(2026, 10, 4, hour: 0))
        XCTAssertEqual(taskRows(in: model), ["Water plants"])

        model.select(harness.date(2026, 10, 5, hour: 0))
        XCTAssertTrue(model.selectedSummary.isEmpty)
    }

    func testTaskRowsReadAsCompletedToVoiceOver() throws {
        let taskList = try makeTaskList()
        let task = try completeTask("Pay rent", in: taskList, on: harness.date(2026, 10, 3))
        let model = makeModel(taskList)

        model.select(harness.date(2026, 10, 3, hour: 0))

        let rows = model.selectedSummary.sections.first { $0.kind == .tasks }?.rows ?? []
        XCTAssertEqual(rows.map(\.accessibilityValue), ["Completed"])
        XCTAssertEqual(rows.map(\.accessibilityIdentifier), ["month-summary-row-task-\(task.id.uuidString)"])
    }

    // MARK: Recomputing

    func testCompletingAndUncompletingATaskOnTodayUpdatesTodaysMarkAndRows() throws {
        let taskList = try makeTaskList()
        let task = try XCTUnwrap(taskList.addTask(text: "Pay rent"))
        let model = makeModel(taskList)
        XCTAssertEqual(try taskMark(6, in: model), .empty)
        XCTAssertTrue(model.selectedSummary.isEmpty)

        taskList.toggleTask(id: task.id)
        XCTAssertEqual(try taskMark(6, in: model), .filled)
        XCTAssertEqual(try day(6, in: model).accessibilityLabel, "Tuesday, October 6, Today, 1 task completed")
        XCTAssertEqual(taskRows(in: model), ["Pay rent"])

        taskList.toggleTask(id: task.id)
        XCTAssertEqual(try taskMark(6, in: model), .empty)
        XCTAssertTrue(model.selectedSummary.isEmpty)
    }

    func testDeletingACompletedTaskRemovesItsMarkAndRow() throws {
        let taskList = try makeTaskList()
        let task = try completeTask("Pay rent", in: taskList, on: harness.date(2026, 10, 6))
        let model = makeModel(taskList)
        XCTAssertEqual(try taskMark(6, in: model), .filled)

        taskList.deleteTask(id: task.id)

        XCTAssertEqual(try taskMark(6, in: model), .empty)
    }

    func testRenamingACompletedTaskUpdatesItsRow() throws {
        let taskList = try makeTaskList()
        let task = try completeTask("Pay rnet", in: taskList, on: harness.date(2026, 10, 6))
        let model = makeModel(taskList)

        taskList.editTask(id: task.id, text: "Pay rent")

        XCTAssertEqual(taskRows(in: model), ["Pay rent"])
    }

    // MARK: Other months

    func testAnotherMonthShowsItsOwnTaskMarksAndRowsStraightAway() throws {
        let taskList = try makeTaskList()
        try completeTask("Old chore", in: taskList, on: harness.date(2026, 9, 28))
        try completeTask("This month", in: taskList, on: harness.date(2026, 10, 2))
        let model = makeModel(taskList)
        XCTAssertEqual(try taskMark(2, in: model), .filled)

        model.showPreviousMonth()

        XCTAssertEqual(try taskMark(28, in: model), .filled)
        XCTAssertEqual(try taskMark(27, in: model), .empty)
        model.select(harness.date(2026, 9, 28, hour: 0))
        XCTAssertEqual(taskRows(in: model), ["Old chore"])
    }

    func testTasksCompletedInAnEarlierYearShowOnTheirDay() throws {
        let taskList = try makeTaskList()
        try completeTask("Last year", in: taskList, on: harness.date(2025, 12, 31))
        let model = makeModel(taskList)

        for _ in 0..<10 { model.showPreviousMonth() }

        XCTAssertEqual(model.headerText, "December 2025")
        XCTAssertEqual(try taskMark(31, in: model), .filled)
    }

    // MARK: Days after Today

    func testATaskRecordedAgainstALaterDayShowsNoMarkAndNoRowUntilThatDayArrives() throws {
        let taskList = try makeTaskList()
        // The clock was ahead when this was completed, as after a time zone or clock change.
        try completeTask("From the future", in: taskList, on: harness.date(2026, 10, 9))
        let model = makeModel(taskList)

        XCTAssertEqual(try taskMark(9, in: model), .empty)
        model.select(harness.date(2026, 10, 9, hour: 0))
        XCTAssertTrue(taskRows(in: model).isEmpty)
        XCTAssertTrue(model.selectedSummary.isEmpty)

        harness.setNow(harness.date(2026, 10, 9))
        model.refresh()

        XCTAssertEqual(try taskMark(9, in: model), .filled)
        XCTAssertEqual(taskRows(in: model), ["From the future"])
    }
}
