import SwiftData
import XCTest

/// Shared setup for tests that run phone and standalone `HabitListStore`s on an in-memory
/// `ModelContainer`. A test that reopens a store reuses the same container.
@MainActor
enum HabitStorage {
    static func makeContainer() throws -> ModelContainer {
        try KyoModelContainer.make(inMemory: true)
    }

    /// Stores `habits` in `container` as if an earlier launch had saved them.
    static func seed(_ habits: [Habit], in container: ModelContainer) {
        SwiftDataHabitContent(modelContainer: container).save(habits)
    }

    /// Stores habits decoded from the JSON an earlier version of the app persisted.
    static func seed(json: String, in container: ModelContainer) throws {
        seed(try JSONDecoder().decode([Habit].self, from: Data(json.utf8)), in: container)
    }

    /// The number of records of `type` in `container`, whichever habit they belong to.
    static func recordCount<Model: PersistentModel>(_ type: Model.Type, in container: ModelContainer) throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<Model>())
    }
}
