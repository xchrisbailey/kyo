import Foundation
import SwiftData

/// Version 1 of Kyo's SwiftData schema: tasks and habits. See
/// docs/adr/0004-swiftdata-cloudkit-ready-storage.md.
enum KyoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self]
    }
}

/// Version 2 adds memos and their voice audio, and nothing else changes. It hasn't shipped, so
/// memo models that arrive before it does (photos) join it; after it ships, they need a further
/// additive version.
enum KyoSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        KyoSchemaV1.models + [MemoRecord.self, MemoAudioRecord.self]
    }
}

enum KyoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [KyoSchemaV1.self, KyoSchemaV2.self]
    }

    /// Adding a model is a lightweight migration: existing tasks and habits are untouched.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: KyoSchemaV1.self, toVersion: KyoSchemaV2.self)]
    }
}

enum KyoModelContainer {
    /// UI tests set this to `1` to give the phone a fresh in-memory store and no sync.
    static let inMemoryEnvironmentKey = "KYO_IN_MEMORY_STORE"

    static var isInMemoryRequested: Bool {
        ProcessInfo.processInfo.environment[inMemoryEnvironmentKey] == "1"
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
        let schema = Schema(versionedSchema: KyoSchemaV2.self)
        let configuration = configuration(schema)
        return try ModelContainer(
            for: schema,
            migrationPlan: KyoMigrationPlan.self,
            configurations: configuration
        )
    }
}
