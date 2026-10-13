import Foundation
import SwiftData

/// Version 1 of Kyo's SwiftData schema: tasks and habits. See
/// docs/adr/0004-swiftdata-cloudkit-ready-storage.md.
enum KyoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [PrePlannedTaskSchema.TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self]
    }
}

/// Version 2 adds memos, their voice audio and their photos, and nothing else changes. It hasn't
/// shipped, so memo models that arrive before it does join it; after it ships, they need a
/// further additive version.
enum KyoSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        KyoSchemaV1.models + [MemoRecord.self, MemoAudioRecord.self, MemoPhotoRecord.self]
    }
}

/// Version 3 adds optional planned-day attributes to tasks.
enum KyoSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [PreProjectTaskSchema.TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self,
         MemoRecord.self, MemoAudioRecord.self, MemoPhotoRecord.self]
    }
}

/// Version 4 adds projects and explicit project-task availability.
enum KyoSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self,
         MemoRecord.self, MemoAudioRecord.self, MemoPhotoRecord.self, ProjectRecord.self]
    }
}

enum KyoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [KyoSchemaV1.self, KyoSchemaV2.self, KyoSchemaV3.self, KyoSchemaV4.self]
    }

    /// New models and optional task attributes migrate without replacing existing content.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: KyoSchemaV1.self, toVersion: KyoSchemaV2.self),
         .lightweight(fromVersion: KyoSchemaV2.self, toVersion: KyoSchemaV3.self),
         .lightweight(fromVersion: KyoSchemaV3.self, toVersion: KyoSchemaV4.self)]
    }
}

enum KyoModelContainer {
    /// UI tests set this to `1` to give the phone a fresh in-memory store and no sync.
    static let inMemoryEnvironmentKey = "KYO_IN_MEMORY_STORE"

    static var isInMemoryRequested: Bool {
        isInMemoryRequested(in: ProcessInfo.processInfo.environment)
    }

    /// Whether `environment` asks for an in-memory launch. The one place that rule is written.
    static func isInMemoryRequested(in environment: [String: String]) -> Bool {
        environment[inMemoryEnvironmentKey] == "1"
    }

    /// Opens Kyo's store: on disk in the app's own container by default, or in memory. The
    /// store never syncs through CloudKit until that effort explicitly turns it on, so an
    /// unrelated iCloud entitlement can't enable it.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        try make(configuration: { schema in
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        })
    }

    /// Opens the store at `url`, migrating it to the current schema. For tests that reopen a
    /// store written by an earlier version.
    static func make(storeURL url: URL) throws -> ModelContainer {
        try make(configuration: { schema in
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        })
    }

    private static func make(configuration: (Schema) -> ModelConfiguration) throws -> ModelContainer {
        let schema = Schema(versionedSchema: KyoSchemaV4.self)
        let configuration = configuration(schema)
        return try ModelContainer(
            for: schema,
            migrationPlan: KyoMigrationPlan.self,
            configurations: configuration
        )
    }
}

/// Frozen task shape used by installations before planned days.
enum PrePlannedTaskSchema {
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

        init(task: DailyTask) {
            id = task.id
            text = task.text
            creationOrder = task.creationOrder
            isComplete = task.isComplete
            completedEra = task.completedOn?.era
            completedYear = task.completedOn?.year
            completedMonth = task.completedOn?.month
            completedDay = task.completedOn?.day
        }

        var completedOn: TaskCompletionDay? {
            guard let completedYear, let completedMonth, let completedDay else { return nil }
            return TaskCompletionDay(era: completedEra, year: completedYear, month: completedMonth, day: completedDay)
        }

        var task: DailyTask {
            DailyTask(
                id: id,
                text: text,
                creationOrder: creationOrder,
                isComplete: isComplete,
                completedOn: completedOn
            )
        }

        /// Copies `task`'s fields onto this record, touching a property only when it differs so an
        /// unchanged record stays clean.
        func update(from task: DailyTask) {
            if text != task.text { text = task.text }
            if creationOrder != task.creationOrder { creationOrder = task.creationOrder }
            if isComplete != task.isComplete { isComplete = task.isComplete }
            let day = task.completedOn
            if completedEra != day?.era { completedEra = day?.era }
            if completedYear != day?.year { completedYear = day?.year }
            if completedMonth != day?.month { completedMonth = day?.month }
            if completedDay != day?.day { completedDay = day?.day }
        }
    }
}

/// Frozen task shape installed before Projects.
enum PreProjectTaskSchema {
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

        init(task: DailyTask) {
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
                plannedOn: plannedOn
            )
        }

        /// Copies `task`'s fields onto this record, touching a property only when it differs so an
        /// unchanged record stays clean.
        func update(from task: DailyTask) {
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
}
