import Foundation
import SwiftData

/// The stored form of a `DailyTask` on the phone and iPad. Follows docs/adr/0004: no unique
/// constraints (duplicates are removed by id in app code), and every attribute has a default
/// or is optional so the schema stays CloudKit-ready. The completion day is stored as flat
/// integer fields matching `TaskCompletionDay`, never as a timestamp.
@Model
final class TaskRecord {
    var id: UUID = UUID()
    var text: String = ""
    var creationOrder: Int64 = 0
    var isComplete: Bool = false
    var completedEra: Int?
    var completedYear: Int?
    var completedMonth: Int?
    var completedDay: Int?

    var plannedEra: Int?
    var plannedYear: Int?
    var plannedMonth: Int?
    var plannedDay: Int?

    var projectID: UUID?
    var isUnscheduled: Bool?

    init(task: DailyTask) {
        projectID = task.projectID
        isUnscheduled = task.isUnscheduled
        id = task.id
        text = task.text
        creationOrder = task.creationOrder
        isComplete = task.isComplete
        completedEra = task.completedOn?.era
        completedYear = task.completedOn?.year
        completedMonth = task.completedOn?.month
        completedDay = task.completedOn?.day
        plannedEra = task.plannedOn?.era
        plannedYear = task.plannedOn?.year
        plannedMonth = task.plannedOn?.month
        plannedDay = task.plannedOn?.day
    }

    var completedOn: TaskCompletionDay? {
        guard let completedYear, let completedMonth, let completedDay else { return nil }
        return TaskCompletionDay(era: completedEra, year: completedYear, month: completedMonth, day: completedDay)
    }

    var plannedOn: TaskPlannedDay? {
        guard let plannedYear, let plannedMonth, let plannedDay else { return nil }
        return TaskPlannedDay(era: plannedEra, year: plannedYear, month: plannedMonth, day: plannedDay)
    }

    var task: DailyTask {
        DailyTask(
            id: id,
            text: text,
            creationOrder: creationOrder,
            isComplete: isComplete,
            completedOn: completedOn,
            plannedOn: plannedOn,
            projectID: projectID,
            isUnscheduled: isUnscheduled ?? false
        )
    }

    /// Copies `task`'s fields onto this record, touching a property only when it differs so an
    /// unchanged record stays clean.
    func update(from task: DailyTask) {
        if projectID != task.projectID { projectID = task.projectID }
        if isUnscheduled != task.isUnscheduled { isUnscheduled = task.isUnscheduled }
        if text != task.text { text = task.text }
        if creationOrder != task.creationOrder { creationOrder = task.creationOrder }
        if isComplete != task.isComplete { isComplete = task.isComplete }
        let planned = task.plannedOn
        if plannedEra != planned?.era { plannedEra = planned?.era }
        if plannedYear != planned?.year { plannedYear = planned?.year }
        if plannedMonth != planned?.month { plannedMonth = planned?.month }
        if plannedDay != planned?.day { plannedDay = planned?.day }
        let day = task.completedOn
        if completedEra != day?.era { completedEra = day?.era }
        if completedYear != day?.year { completedYear = day?.year }
        if completedMonth != day?.month { completedMonth = day?.month }
        if completedDay != day?.day { completedDay = day?.day }
    }
}
