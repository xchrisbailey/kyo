import SwiftData
import XCTest

/// Opening a store written before memos existed (`KyoSchemaV1`) with the current schema keeps
/// its tasks and habits and adds an empty memo store.
@MainActor
final class MemoSchemaMigrationTests: XCTestCase {
    /// The plan the app shipped with before memos: one schema, no stages.
    private enum VersionOneOnlyPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] { [KyoSchemaV1.self] }
        static var stages: [MigrationStage] { [] }
    }

    func testAStoreFromBeforeMemosMigratesAndKeepsItsTasksAndHabits() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoSchemaMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Kyo.store")

        do {
            let schema = Schema(versionedSchema: KyoSchemaV1.self)
            let old = try ModelContainer(
                for: schema,
                migrationPlan: VersionOneOnlyPlan.self,
                configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            )
            SwiftDataTaskContent(modelContainer: old).save([DailyTask(text: "Written before memos", creationOrder: 0)])
            SwiftDataHabitContent(modelContainer: old).save([Habit(name: "Stretch", order: 0)])
        }

        let migrated = try KyoModelContainer.make(storeURL: storeURL)

        XCTAssertEqual(SwiftDataTaskContent(modelContainer: migrated).load().map(\.text), ["Written before memos"])
        XCTAssertEqual(SwiftDataHabitContent(modelContainer: migrated).load().map(\.name), ["Stretch"])
        let store = MemoStore(modelContainer: migrated)
        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertNotNil(store.addWrittenMemo(text: "First memo"))
        XCTAssertEqual(MemoStore(modelContainer: migrated).memos.map(\.title), ["First memo"])
    }

    func testTheMigrationPlanOnlyAddsModels() {
        XCTAssertEqual(KyoMigrationPlan.schemas.count, 2)
        XCTAssertEqual(KyoMigrationPlan.stages.count, 1)
        let v1 = Set(KyoSchemaV1.models.map { String(describing: $0) })
        let v2 = Set(KyoSchemaV2.models.map { String(describing: $0) })
        XCTAssertTrue(v1.isSubset(of: v2))
        XCTAssertEqual(v2.subtracting(v1), ["MemoRecord", "MemoAudioRecord", "MemoPhotoRecord"])
    }
}
