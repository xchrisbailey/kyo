import SwiftData
import XCTest

@MainActor
final class TaskListBehaviorTests: XCTestCase {
    func testAddingTasksTrimsTextAndPreservesCreationOrder() throws {
        let container = try makeContainer()
        let list: any TaskListBehavior = TaskListStore(modelContainer: container)

        let first = try XCTUnwrap(list.addTask(text: "  First task  "))
        let second = try XCTUnwrap(list.addTask(text: "Second task"))

        XCTAssertEqual(list.tasks.map(\.text), ["First task", "Second task"])
        XCTAssertEqual(list.tasks.map(\.creationOrder), [0, 1])
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(list.taskCount, 2)
        XCTAssertEqual(list.incompleteCount, 2)
    }

    func testBlankInputDoesNotCreateATask() throws {
        let list: any TaskListBehavior = TaskListStore(modelContainer: try makeContainer())

        XCTAssertNil(list.addTask(text: " \n\t "))
        XCTAssertTrue(list.tasks.isEmpty)
        XCTAssertEqual(list.taskCount, 0)
    }

    func testEditingTrimsTextAndPreservesTaskIdentityOrderAndCompletion() throws {
        let container = try makeContainer()
        let calendar = Calendar(identifier: .gregorian)
        let completedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        let list = TaskListStore(
            modelContainer: container,
            now: { completedAt },
            calendar: calendar
        )
        let first = try XCTUnwrap(list.addTask(text: "First"))
        let second = try XCTUnwrap(list.addTask(text: "Second"))
        _ = list.toggleTask(id: first.id)
        let completedFirst = try XCTUnwrap(list.tasks.first { $0.id == first.id })

        let edited = try XCTUnwrap(list.editTask(id: first.id, text: "  Renamed first  "))

        XCTAssertEqual(edited.id, first.id)
        XCTAssertEqual(edited.text, "Renamed first")
        XCTAssertEqual(edited.creationOrder, first.creationOrder)
        XCTAssertEqual(edited.isComplete, completedFirst.isComplete)
        XCTAssertEqual(edited.completedOn, completedFirst.completedOn)
        XCTAssertEqual(list.tasks.map(\.id), [second.id, first.id])
        XCTAssertEqual(list.completedCount, 1)
        XCTAssertEqual(list.incompleteCount, 1)

        // Reopen on the same local day so today's completed task remains visible.
        let reopened = TaskListStore(
            modelContainer: container,
            now: { completedAt },
            calendar: calendar
        )
        XCTAssertEqual(reopened.tasks, list.tasks)
    }

    func testBlankOrUnknownEditDoesNotChangeTask() throws {
        let list = TaskListStore(modelContainer: try makeContainer())
        let task = try XCTUnwrap(list.addTask(text: "Keep this"))

        XCTAssertNil(list.editTask(id: task.id, text: " \n\t "))
        XCTAssertNil(list.editTask(id: UUID(), text: "Unknown"))
        XCTAssertEqual(list.tasks, [task])
    }

    func testDeletingTaskUpdatesCountsAndPersists() throws {
        let container = try makeContainer()
        let list = TaskListStore(modelContainer: container)
        let first = try XCTUnwrap(list.addTask(text: "First"))
        _ = list.addTask(text: "Second")
        let completedFirst = try XCTUnwrap(list.toggleTask(id: first.id))
        XCTAssertEqual(list.completedCount, 1)

        XCTAssertEqual(list.deleteTask(id: first.id), completedFirst)
        XCTAssertNil(list.deleteTask(id: UUID()))
        XCTAssertEqual(list.taskCount, 1)
        XCTAssertEqual(list.completedCount, 0)
        XCTAssertEqual(list.incompleteCount, 1)
        XCTAssertEqual(list.tasks.map(\.text), ["Second"])
        XCTAssertEqual(TaskListStore(modelContainer: container).tasks, list.tasks)
    }

    func testSavedTasksSurviveReopeningTheList() throws {
        let container = try makeContainer()
        let firstList: any TaskListBehavior = TaskListStore(modelContainer: container)
        let saved = try XCTUnwrap(firstList.addTask(text: "Remember this"))

        let reopenedList: any TaskListBehavior = TaskListStore(modelContainer: container)

        XCTAssertEqual(reopenedList.tasks, [saved])
        XCTAssertEqual(reopenedList.taskCount, 1)
        XCTAssertEqual(reopenedList.incompleteCount, 1)
    }

    func testCompletingAndReopeningTasksGroupsByStateAndPreservesCreationOrder() throws {
        let calendar = Calendar(identifier: .gregorian)
        let completionDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 16)))
        let list = TaskListStore(
            modelContainer: try makeContainer(),
            now: { completionDate },
            calendar: calendar
        )
        let first = try XCTUnwrap(list.addTask(text: "First"))
        let second = try XCTUnwrap(list.addTask(text: "Second"))
        let third = try XCTUnwrap(list.addTask(text: "Third"))

        let completedSecond = try XCTUnwrap(list.toggleTask(id: second.id))

        XCTAssertTrue(completedSecond.isComplete)
        XCTAssertEqual(completedSecond.completedOn, TaskCompletionDay(date: completionDate, calendar: calendar))
        XCTAssertEqual(list.tasks.map(\.text), ["First", "Third", "Second"])
        XCTAssertEqual(list.completedCount, 1)
        XCTAssertEqual(list.incompleteCount, 2)

        _ = list.toggleTask(id: first.id)
        XCTAssertEqual(list.tasks.map(\.text), ["Third", "First", "Second"])
        XCTAssertEqual(list.tasks.filter { !$0.isComplete }.map(\.creationOrder), [third.creationOrder])

        let reopenedSecond = try XCTUnwrap(list.toggleTask(id: second.id))
        XCTAssertFalse(reopenedSecond.isComplete)
        XCTAssertNil(reopenedSecond.completedOn)
        XCTAssertEqual(list.tasks.map(\.text), ["Second", "Third", "First"])
        XCTAssertEqual(list.tasks.filter { !$0.isComplete }.map(\.creationOrder), [second.creationOrder, third.creationOrder])

        _ = list.toggleTask(id: first.id)
        XCTAssertEqual(list.tasks.map(\.text), ["First", "Second", "Third"])
        XCTAssertEqual(list.completedCount, 0)
        XCTAssertEqual(list.incompleteCount, 3)
    }

    func testCompletionAndCompletionDaySurviveReopeningTheList() throws {
        let container = try makeContainer()
        let calendar = Calendar(identifier: .gregorian)
        let completionDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 23)))
        let firstList = TaskListStore(
            modelContainer: container,
            now: { completionDate },
            calendar: calendar
        )
        let task = try XCTUnwrap(firstList.addTask(text: "Persist completion"))
        _ = firstList.toggleTask(id: task.id)

        let reopenedList = TaskListStore(
            modelContainer: container,
            now: { completionDate },
            calendar: calendar
        )

        XCTAssertEqual(reopenedList.tasks.first?.id, task.id)
        XCTAssertEqual(reopenedList.tasks.first?.completedOn, TaskCompletionDay(date: completionDate, calendar: calendar))
        XCTAssertEqual(reopenedList.completedCount, 1)
        XCTAssertEqual(reopenedList.incompleteCount, 0)
    }

    func testTogglingUnknownTaskDoesNothing() throws {
        let list = TaskListStore(modelContainer: try makeContainer())

        XCTAssertNil(list.toggleTask(id: UUID()))
        XCTAssertTrue(list.tasks.isEmpty)
    }

    func testExistingSavedTaskShapeDecodesWithoutCompletionDay() throws {
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","text":"Saved before completion support","creationOrder":0,"isComplete":false}]
        """.data(using: .utf8)!

        let tasks = try JSONDecoder().decode([DailyTask].self, from: json)

        XCTAssertEqual(tasks.first?.id, id)
        XCTAssertEqual(tasks.first?.text, "Saved before completion support")
        XCTAssertEqual(tasks.first?.completedOn, nil)
        XCTAssertEqual(tasks.first?.isComplete, false)
    }

    func testMidnightRolloverCarriesIncompleteTasksAndKeepsCompletionsOnTheirDay() throws {
        let container = try makeContainer()
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 23, minute: 59)))
        let list = TaskListStore(
            modelContainer: container,
            now: { now },
            calendar: calendar
        )
        let first = try XCTUnwrap(list.addTask(text: "Carry first"))
        let second = try XCTUnwrap(list.addTask(text: "Complete today"))
        let third = try XCTUnwrap(list.addTask(text: "Carry third"))
        _ = list.toggleTask(id: second.id)

        XCTAssertEqual(list.taskCount, 3)
        XCTAssertEqual(list.completedCount, 1)
        XCTAssertEqual(list.incompleteCount, 2)

        now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 0, minute: 1)))
        list.refreshForCurrentDay()

        XCTAssertEqual(list.currentDate, calendar.startOfDay(for: now))
        XCTAssertEqual(list.tasks.map(\.id), [first.id, third.id])
        XCTAssertEqual(list.tasks.map(\.creationOrder), [first.creationOrder, third.creationOrder])
        XCTAssertEqual(list.taskCount, 2)
        XCTAssertEqual(list.completedCount, 0)
        XCTAssertEqual(list.incompleteCount, 2)

        // The completed task is still saved: on its own day, a reopened list shows it completed.
        let completionDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        let sameDay = TaskListStore(modelContainer: container, now: { completionDate }, calendar: calendar)
        let savedCompletion = try XCTUnwrap(sameDay.tasks.first { $0.id == second.id })
        XCTAssertEqual(savedCompletion.completedOn, TaskCompletionDay(date: completionDate, calendar: calendar))
        XCTAssertTrue(savedCompletion.isComplete)

        list.refreshForCurrentDay()
        let reopened = TaskListStore(modelContainer: container, now: { now }, calendar: calendar)
        XCTAssertEqual(reopened.tasks.map(\.id), [first.id, third.id])
        XCTAssertEqual(reopened.taskCount, 2)
    }

    func testMultipleMissedDaysAreIdempotentAndNewTasksFollowCarriedTasks() throws {
        let container = try makeContainer()
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10)))
        let list = TaskListStore(modelContainer: container, now: { now }, calendar: calendar)
        let first = try XCTUnwrap(list.addTask(text: "First"))
        let second = try XCTUnwrap(list.addTask(text: "Second"))
        _ = list.toggleTask(id: first.id)

        now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 10)))
        let reopenedAfterMissedDays = TaskListStore(
            modelContainer: container,
            now: { now },
            calendar: calendar
        )
        XCTAssertEqual(reopenedAfterMissedDays.tasks.map(\.id), [second.id])
        XCTAssertEqual(reopenedAfterMissedDays.completedCount, 0)

        list.refreshForCurrentDay()
        list.refreshForCurrentDay()
        let third = try XCTUnwrap(list.addTask(text: "Added after returning"))

        XCTAssertEqual(list.tasks.map(\.id), [second.id, third.id])
        XCTAssertEqual(list.tasks.map(\.creationOrder), [second.creationOrder, third.creationOrder])
        XCTAssertEqual(list.taskCount, 2)
        XCTAssertEqual(list.completedCount, 0)
        XCTAssertEqual(list.incompleteCount, 2)

        let reopened = TaskListStore(modelContainer: container, now: { now }, calendar: calendar)
        XCTAssertEqual(reopened.tasks, list.tasks)
        XCTAssertEqual(reopened.tasks.filter { !$0.isComplete }.map(\.id), [second.id, third.id])
    }

    func testCollapsedSummaryCountsDoneTasksAndSaysWhenThereAreNone() throws {
        let list: any TaskListBehavior = TaskListStore(modelContainer: try makeContainer())
        XCTAssertEqual(list.collapsedSummary, "No tasks")

        let first = try XCTUnwrap(list.addTask(text: "First"))
        for text in ["Second", "Third", "Fourth", "Fifth"] { _ = list.addTask(text: text) }
        XCTAssertEqual(list.collapsedSummary, "0 of 5 done")

        _ = list.toggleTask(id: first.id)
        let second = try XCTUnwrap(list.tasks.first { $0.text == "Second" })
        _ = list.toggleTask(id: second.id)
        XCTAssertEqual(list.collapsedSummary, "2 of 5 done")

        _ = list.deleteTask(id: first.id)
        XCTAssertEqual(list.collapsedSummary, "1 of 4 done")
    }

    func testCollapsedSummaryCountsCarriedForwardTasksAndDropsYesterdaysCompletedOnes() throws {
        let container = try makeContainer()
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10)))
        let list = TaskListStore(modelContainer: container, now: { now }, calendar: calendar)
        let done = try XCTUnwrap(list.addTask(text: "Done yesterday"))
        _ = list.addTask(text: "Carried")
        _ = list.toggleTask(id: done.id)
        XCTAssertEqual(list.collapsedSummary, "1 of 2 done")

        now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10)))
        list.refreshForCurrentDay()
        XCTAssertEqual(list.collapsedSummary, "0 of 1 done")

        _ = list.addTask(text: "New today")
        XCTAssertEqual(list.collapsedSummary, "0 of 2 done")
    }

    private func makeContainer() throws -> ModelContainer {
        try KyoModelContainer.make(inMemory: true)
    }
}
