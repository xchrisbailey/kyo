import Foundation
import SwiftData

/// Where a `TaskListStore` keeps its task content. In-memory logic always works on
/// `DailyTask` values; this seam only loads and saves them. A failed save is ignored, like
/// the `try?` UserDefaults writes it replaces.
@MainActor
protocol TaskContentPersistence {
    func load() -> [DailyTask]
    func save(_ tasks: [DailyTask])
}

/// The Watch's (`.mirror`) content cache: one JSON array under a UserDefaults key, exactly as
/// before SwiftData.
struct UserDefaultsTaskContent: TaskContentPersistence {
    let userDefaults: UserDefaults
    let key: String

    func load() -> [DailyTask] {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DailyTask].self, from: data) else { return [] }
        return decoded
    }

    func save(_ tasks: [DailyTask]) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        userDefaults.set(data, forKey: key)
    }
}

/// The phone's and any standalone store's content, kept as `TaskRecord`s in the container's
/// main context.
struct SwiftDataTaskContent: TaskContentPersistence {
    let modelContainer: ModelContainer

    private var context: ModelContext { modelContainer.mainContext }

    /// Loads every task, first removing records that share an id (the schema has no unique
    /// constraint, so duplicates are cleaned up here). The record kept is the one that sorts
    /// first by creation order, text, then completion, so the choice never depends on fetch order.
    func load() -> [DailyTask] {
        guard let records = try? context.fetch(FetchDescriptor<TaskRecord>()) else { return [] }
        var kept: [UUID: TaskRecord] = [:]
        for record in records.sorted(by: Self.keepsFirst) where kept[record.id] == nil {
            kept[record.id] = record
        }
        for record in records where kept[record.id] !== record {
            context.delete(record)
        }
        if context.hasChanges {
            try? context.save()
        }
        return kept.values.map(\.task)
    }

    /// Reconciles the stored records with `tasks`: updates changed records, inserts new ones
    /// and deletes ones no longer present, then saves once.
    func save(_ tasks: [DailyTask]) {
        let records = (try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []
        var existing: [UUID: TaskRecord] = [:]
        for record in records.sorted(by: Self.keepsFirst) {
            if existing[record.id] == nil {
                existing[record.id] = record
            } else {
                context.delete(record)
            }
        }
        var missingIDs = Set(existing.keys)
        for task in tasks {
            if let record = existing[task.id] {
                record.update(from: task)
                missingIDs.remove(task.id)
            } else {
                Self.insert(task, into: context)
            }
        }
        for id in missingIDs {
            if let record = existing[id] {
                context.delete(record)
            }
        }
        if context.hasChanges {
            try? context.save()
        }
    }

    /// Inserts `task` as a task record. Doesn't save. Shared with `UserDefaultsImport`.
    static func insert(_ task: DailyTask, into context: ModelContext) {
        context.insert(TaskRecord(task: task))
    }

    private static func keepsFirst(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        if lhs.creationOrder != rhs.creationOrder { return lhs.creationOrder < rhs.creationOrder }
        if lhs.text != rhs.text { return lhs.text < rhs.text }
        return !lhs.isComplete && rhs.isComplete
    }
}
