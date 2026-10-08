import Combine
import Foundation

/// The tasks completed on each day, for Month. Open tasks never appear: a day is marked, and a row is
/// listed, only for a task completed on it.
@MainActor
struct TaskMonthContent: MonthContentSource {
    let kind = MonthKind.tasks
    private let taskList: TaskListStore

    init(taskList: TaskListStore) {
        self.taskList = taskList
    }

    /// Fires after every change to the list, whether or not Today's own tasks changed.
    var changes: AnyPublisher<Void, Never> {
        taskList.$tasks.map { _ in }.eraseToAnyPublisher()
    }

    func content(on days: [Date]) -> [Date: MonthKindDay] {
        var content: [Date: MonthKindDay] = [:]
        for day in taskList.daysWithCompletedTask(in: days) {
            let tasks = taskList.tasksCompleted(on: day)
            content[day] = MonthKindDay(
                mark: .filled,
                phrase: MonthKindDay.countPhrase(tasks.count, one: "task completed", other: "tasks completed"),
                rows: tasks.map { MonthSummaryRow(id: "task-\($0.id.uuidString)", text: $0.text, accessibilityValue: "Completed") }
            )
        }
        return content
    }
}
