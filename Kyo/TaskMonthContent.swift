import Combine
import Foundation

/// Incomplete planned tasks and completion-day history for Month. A task has only its current
/// state here: completing it removes its planned row and adds the actual completion-day row.
@MainActor
final class TaskMonthContent: MonthContentSource {
    let kind = MonthKind.tasks
    private let taskList: TaskListStore
    private var projectsEnabled = true
    private var projects: [Project]
    private var subscriptions = Set<AnyCancellable>()
    let changes: AnyPublisher<Void, Never>

    init(taskList: TaskListStore, projectsPreference: ProjectsPreferenceStore? = nil) {
        self.taskList = taskList
        projects = taskList.projectCatalog
        projectsEnabled = projectsPreference?.isEnabled ?? true
        let subject = PassthroughSubject<Void, Never>()
        changes = subject.eraseToAnyPublisher()
        projectsPreference?.$isEnabled.dropFirst().sink { [weak self] enabled in
            self?.projectsEnabled = enabled
            subject.send()
        }.store(in: &subscriptions)
        taskList.$tasks.dropFirst()
            .sink { _ in subject.send() }
            .store(in: &subscriptions)
        // Published values arrive before the store updates, so retain the received catalog.
        taskList.$projectCatalog.dropFirst()
            .sink { [weak self] projects in
                self?.projects = projects
                subject.send()
            }
            .store(in: &subscriptions)
    }

    func content(on days: [Date]) -> [Date: MonthKindDay] {
        taskContent(on: days, calendar: nil)
    }

    func content(on days: [Date], calendar: Calendar) -> [Date: MonthKindDay] {
        taskContent(on: days, calendar: calendar)
    }

    private func taskContent(on days: [Date], calendar: Calendar?) -> [Date: MonthKindDay] {
        var content: [Date: MonthKindDay] = [:]
        for day in days {
            let planned = taskList.tasksPlanned(on: day, calendar: calendar)
            let completed = taskList.tasksCompleted(on: day, calendar: calendar)
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
        let project = projectsEnabled ? projects.first { $0.id == task.projectID } : nil
        return MonthSummaryRow(id: "task-\(task.id.uuidString)", text: task.text,
                        kind: .task(isComplete: isComplete), projectName: project?.name,
                        accessibilityLabel: project.map { "\(task.text), \($0.name)" }, accessibilityValue: isComplete ? "Completed" : "Planned")
    }

}
