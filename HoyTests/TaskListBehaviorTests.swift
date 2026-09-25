import XCTest

@MainActor
final class TaskListBehaviorTests: XCTestCase {
    func testAddingTasksTrimsTextAndPreservesCreationOrder() throws {
        let defaults = try makeDefaults()
        let list: any TaskListBehavior = TaskListStore(userDefaults: defaults, storageKey: "tasks")

        let first = try XCTUnwrap(list.addTask(text: "  First task  "))
        let second = try XCTUnwrap(list.addTask(text: "Second task"))

        XCTAssertEqual(list.tasks.map(\.text), ["First task", "Second task"])
        XCTAssertEqual(list.tasks.map(\.creationOrder), [0, 1])
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(list.taskCount, 2)
        XCTAssertEqual(list.incompleteCount, 2)
    }

    func testBlankInputDoesNotCreateATask() throws {
        let list: any TaskListBehavior = TaskListStore(userDefaults: try makeDefaults(), storageKey: "tasks")

        XCTAssertNil(list.addTask(text: " \n\t "))
        XCTAssertTrue(list.tasks.isEmpty)
        XCTAssertEqual(list.taskCount, 0)
    }

    func testSavedTasksSurviveReopeningTheList() throws {
        let defaults = try makeDefaults()
        let firstList: any TaskListBehavior = TaskListStore(userDefaults: defaults, storageKey: "tasks")
        let saved = try XCTUnwrap(firstList.addTask(text: "Remember this"))

        let reopenedList: any TaskListBehavior = TaskListStore(userDefaults: defaults, storageKey: "tasks")

        XCTAssertEqual(reopenedList.tasks, [saved])
        XCTAssertEqual(reopenedList.taskCount, 1)
        XCTAssertEqual(reopenedList.incompleteCount, 1)
    }

    func testCompletingAndReopeningTasksGroupsByStateAndPreservesCreationOrder() throws {
        let calendar = Calendar(identifier: .gregorian)
        let completionDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 16)))
        let list = TaskListStore(
            userDefaults: try makeDefaults(),
            storageKey: "tasks",
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
        let defaults = try makeDefaults()
        let calendar = Calendar(identifier: .gregorian)
        let completionDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 23)))
        let firstList = TaskListStore(
            userDefaults: defaults,
            storageKey: "tasks",
            now: { completionDate },
            calendar: calendar
        )
        let task = try XCTUnwrap(firstList.addTask(text: "Persist completion"))
        _ = firstList.toggleTask(id: task.id)

        let reopenedList = TaskListStore(userDefaults: defaults, storageKey: "tasks", calendar: calendar)

        XCTAssertEqual(reopenedList.tasks.first?.id, task.id)
        XCTAssertEqual(reopenedList.tasks.first?.completedOn, TaskCompletionDay(date: completionDate, calendar: calendar))
        XCTAssertEqual(reopenedList.completedCount, 1)
        XCTAssertEqual(reopenedList.incompleteCount, 0)
    }

    func testTogglingUnknownTaskDoesNothing() throws {
        let list = TaskListStore(userDefaults: try makeDefaults(), storageKey: "tasks")

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

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "TaskListBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
