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

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "TaskListBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
