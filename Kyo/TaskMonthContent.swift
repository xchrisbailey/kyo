import Combine
import Foundation

/// Incomplete planned tasks and completion-day history for Month. A task has only its current
/// state here: completing it removes its planned row and adds the actual completion-day row.
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
        for day in days {
            let planned = taskList.tasksPlanned(on: day)
            let completed = taskList.tasksCompleted(on: day)
            guard !planned.isEmpty || !completed.isEmpty else { continue }
            let phrases = [
                planned.isEmpty ? nil : MonthKindDay.countPhrase(planned.count, one: "task planned", other: "tasks planned"),
                completed.isEmpty ? nil : MonthKindDay.countPhrase(completed.count, one: "task completed", other: "tasks completed")
            ].compactMap { $0 }
            content[day] = MonthKindDay(
                mark: planned.isEmpty ? .filled : (completed.isEmpty ? .hollow : .mixed),
                phrase: phrases.joined(separator: ", "),
                rows: planned.map { row($0, isComplete: false) } + completed.map { row($0, isComplete: true) }
            )
        }
        return content
    }
    private func row(_ task: DailyTask, isComplete: Bool) -> MonthSummaryRow {
        MonthSummaryRow(id: "task-\(task.id.uuidString)", text: task.text,
                        kind: .task(isComplete: isComplete), accessibilityValue: isComplete ? "Completed" : "Planned")
    }

}
