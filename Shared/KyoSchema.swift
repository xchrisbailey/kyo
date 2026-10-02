import Foundation
import SwiftData

/// Version 1 of Kyo's SwiftData schema. Memo models are added here, or in a later additive
/// version, as they arrive. See docs/adr/0004-swiftdata-cloudkit-ready-storage.md.
enum KyoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TaskRecord.self, HabitRecord.self, HabitCheckOffRecord.self, HabitScheduleRecord.self]
    }
}

enum KyoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [KyoSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
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
        let schema = Schema(versionedSchema: KyoSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: KyoMigrationPlan.self,
            configurations: configuration
        )
    }
}
