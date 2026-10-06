import XCTest

/// What the share sheet receives for a **Task**, through `TaskSharePayload`: the saved text as one
/// item, exactly as saved, the same for a completed Task and an unfinished one. The share sheet
/// itself is checked on device.
final class TaskShareBehaviorTests: XCTestCase {
    func testSharesTheSavedTextAsTheOnlyItem() {
        let task = DailyTask(text: "Draft the release notes", creationOrder: 0)

        let payload = TaskSharePayload.make(for: task)

        XCTAssertEqual(payload.text, "Draft the release notes")
        XCTAssertEqual(payload.activityItems.count, 1)
        XCTAssertEqual(payload.activityItems.first as? String, "Draft the release notes")
    }

    func testAddsNothingAndChangesNothingInTheText() {
        let text = "  Call Sam — re: \"Q3\" plan 🚀\nsecond line  "
        let task = DailyTask(text: text, creationOrder: 3)

        XCTAssertEqual(TaskSharePayload.make(for: task).text, text)
    }

    func testACompletedTaskSharesTheSameAsAnUnfinishedOne() {
        let day = TaskCompletionDay(era: 1, year: 2026, month: 10, day: 5)
        let open = DailyTask(text: "Water the plants", creationOrder: 0)
        let done = DailyTask(text: "Water the plants", creationOrder: 0, isComplete: true, completedOn: day)

        XCTAssertEqual(TaskSharePayload.make(for: done), TaskSharePayload.make(for: open))
    }
}
