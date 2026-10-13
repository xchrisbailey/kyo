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

/// Version 2 adds the installed memo and media graph; its shape stays frozen.
enum KyoSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        KyoSchemaV1.models + [PreProjectMemoSchema.MemoRecord.self, PreProjectMemoSchema.MemoAudioRecord.self, PreProjectMemoSchema.MemoPhotoRecord.self]
    }
}

/// Version 3 adds optional planned-day attributes to tasks.
enum KyoSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [PreProjectTaskSchema.TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self,
         PreProjectMemoSchema.MemoRecord.self, PreProjectMemoSchema.MemoAudioRecord.self, PreProjectMemoSchema.MemoPhotoRecord.self]
    }
}

/// Version 4 adds projects and explicit project-task availability.
enum KyoSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self,
         PreProjectMemoSchema.MemoRecord.self, PreProjectMemoSchema.MemoAudioRecord.self, PreProjectMemoSchema.MemoPhotoRecord.self, PreArchiveProjectSchema.ProjectRecord.self]
    }
}

/// Version 5 adds optional project identity to memos while retaining their day and media.
enum KyoSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self,
         MemoRecord.self, MemoAudioRecord.self, MemoPhotoRecord.self, PreArchiveProjectSchema.ProjectRecord.self]
    }
}

/// Version 6 adds project archive state without changing retained content.
enum KyoSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self,
         MemoRecord.self, MemoAudioRecord.self, MemoPhotoRecord.self, ProjectRecord.self]
    }
}

/// Frozen project shape installed in versions 4 and 5.
enum PreArchiveProjectSchema {
    @Model
    final class ProjectRecord {
        var id: UUID = UUID()
        var name: String = ""
        var creationOrder: Int64 = 0

        init(project: Project) {
            id = project.id
            name = project.name
            creationOrder = project.creationOrder
        }
    }
}

enum KyoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [KyoSchemaV1.self, KyoSchemaV2.self, KyoSchemaV3.self, KyoSchemaV4.self, KyoSchemaV5.self, KyoSchemaV6.self]
    }

    /// New models and optional task attributes migrate without replacing existing content.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: KyoSchemaV1.self, toVersion: KyoSchemaV2.self),
         .lightweight(fromVersion: KyoSchemaV2.self, toVersion: KyoSchemaV3.self),
         .lightweight(fromVersion: KyoSchemaV3.self, toVersion: KyoSchemaV4.self),
         .lightweight(fromVersion: KyoSchemaV4.self, toVersion: KyoSchemaV5.self),
         .lightweight(fromVersion: KyoSchemaV5.self, toVersion: KyoSchemaV6.self)]
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
        let schema = Schema(versionedSchema: KyoSchemaV6.self)
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

/// Frozen memo and media graph installed before memo project assignment.
enum PreProjectMemoSchema {
    @Model
    final class MemoRecord {
        var id: UUID = UUID()
        /// `Memo.Kind.rawValue`, stored as a string so a later kind needs no migration.
        var kindRaw: String = Memo.Kind.written.rawValue
        var createdAt: Date = Date(timeIntervalSince1970: 0)
        var dayEra: Int?
        var dayYear: Int = 0
        var dayMonth: Int = 0
        var dayDay: Int = 0
        /// A written memo's text, or a voice memo's transcript.
        var text: String = ""
        var durationSeconds: Double = 0
        /// `Memo.TranscriptState.rawValue` for a voice memo; empty for a written memo.
        var transcriptStateRaw: String = ""
        var stoppedAtCap: Bool = false
        /// `TranscriptRetry.rawValue`: whether and when a No transcript voice memo retries by itself.
        var transcriptRetryRaw: String = ""
        /// The device language (`Locale.identifier`) when transcription found it unsupported, so a
        /// later change of language retries.
        var transcriptLocaleIdentifier: String = ""
        /// A voice memo's generated or user title; empty means the "Voice memo" fallback.
        var title: String = ""
        /// Whether the user named the voice memo, so a generated title never replaces it.
        var titleIsUserSet: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \MemoAudioRecord.memo) var audio: MemoAudioRecord?
        @Relationship(deleteRule: .cascade, inverse: \MemoPhotoRecord.memo) var photos: [MemoPhotoRecord]?

        init(
            id: UUID = UUID(),
            kind: Memo.Kind,
            createdAt: Date,
            day: TaskCompletionDay,
            text: String,
            durationSeconds: Double = 0,
            transcriptState: Memo.TranscriptState? = nil,
            stoppedAtCap: Bool = false
        ) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.createdAt = createdAt
            self.dayEra = day.era
            self.dayYear = day.year
            self.dayMonth = day.month
            self.dayDay = day.day
            self.text = text
            self.durationSeconds = durationSeconds
            self.transcriptStateRaw = transcriptState?.rawValue ?? ""
            self.stoppedAtCap = stoppedAtCap
        }

        var kind: Memo.Kind {
            Memo.Kind(rawValue: kindRaw) ?? .written
        }

        var day: TaskCompletionDay {
            TaskCompletionDay(era: dayEra, year: dayYear, month: dayMonth, day: dayDay)
        }

        var transcriptRetry: TranscriptRetry {
            get { TranscriptRetry(rawValue: transcriptRetryRaw) ?? .never }
            set { transcriptRetryRaw = newValue.rawValue }
        }

        var transcriptState: Memo.TranscriptState? {
            get { Memo.TranscriptState(rawValue: transcriptStateRaw) }
            set { transcriptStateRaw = newValue?.rawValue ?? "" }
        }

        /// The photos in the order they were added.
        var orderedPhotos: [MemoPhotoRecord] {
            (photos ?? []).sorted { lhs, rhs in
                lhs.order != rhs.order ? lhs.order < rhs.order : lhs.id.uuidString < rhs.id.uuidString
            }
        }

        var memo: Memo {
            Memo(
                id: id,
                kind: kind,
                createdAt: createdAt,
                day: day,
                text: text,
                duration: durationSeconds,
                transcriptState: kind == .voice ? (transcriptState ?? .noTranscript) : nil,
                stoppedAtCap: stoppedAtCap,
                voiceTitle: kind == .voice ? title : "",
                isTitleUserSet: kind == .voice && titleIsUserSet,
                photoIDs: orderedPhotos.map(\.id)
            )
        }
    }

    @Model
    final class MemoAudioRecord {
        var id: UUID = UUID()
        /// AAC, mono, 48 kbps.
        @Attribute(.externalStorage) var data: Data?
        var memo: MemoRecord?

        init(id: UUID = UUID(), data: Data) {
            self.id = id
            self.data = data
        }
    }

    @Model
    final class MemoPhotoRecord {
        var id: UUID = UUID()
        /// Where the photo sits among its memo's photos: ascending, in the order they were added. A
        /// removed photo leaves a gap, which is harmless.
        var order: Int = 0
        /// HEIC, longest edge at most 2048 px. The original isn't kept.
        @Attribute(.externalStorage) var data: Data?
        /// A small JPEG kept inline, so rows can show the photo without reading `data`.
        var thumbnail: Data?
        var memo: MemoRecord?

        init(id: UUID = UUID(), order: Int, data: Data, thumbnail: Data) {
            self.id = id
            self.order = order
            self.data = data
            self.thumbnail = thumbnail
        }
    }
}
