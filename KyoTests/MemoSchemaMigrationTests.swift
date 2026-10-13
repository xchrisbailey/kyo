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
            old.mainContext.insert(PrePlannedTaskSchema.TaskRecord(task: DailyTask(text: "Written before memos", creationOrder: 0)))
            try old.mainContext.save()
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

    func testInstalledMemoMediaGraphMigratesAndReopensBeforeAndAfterProjectAssignment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let day = TaskCompletionDay(era: 1, year: 2026, month: 10, day: 10)
        let writtenID = UUID()
        let voiceID = UUID()
        let photoID = UUID()
        let photoBytes = Data(repeating: 9, count: 150_000)
        let audioBytes = Data(repeating: 7, count: 150_000)
        let createdAt = Date(timeIntervalSince1970: 1_791_590_400)
        do {
            let schema = Schema(versionedSchema: KyoSchemaV4.self)
            let old = try ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let written = PreProjectMemoSchema.MemoRecord(id: writtenID, kind: .written, createdAt: createdAt,
                day: day, text: "Installed written memo")
            written.photos = [PreProjectMemoSchema.MemoPhotoRecord(id: photoID, order: 0,
                data: photoBytes, thumbnail: Data([1, 2]))]
            old.mainContext.insert(written)
            let voice = PreProjectMemoSchema.MemoRecord(id: voiceID, kind: .voice, createdAt: createdAt,
                day: day, text: "Installed transcript", durationSeconds: 4, transcriptState: .transcribed, stoppedAtCap: true)
            voice.title = "Installed voice title"
            voice.titleIsUserSet = true
            voice.audio = PreProjectMemoSchema.MemoAudioRecord(data: audioBytes)
            old.mainContext.insert(voice)
            try old.mainContext.save()
        }
        var projectID: UUID?
        do {
            let migrated = try KyoModelContainer.make(storeURL: url)
            let store = MemoStore(modelContainer: migrated)
            let written = try XCTUnwrap(store.memo(id: writtenID))
            let voice = try XCTUnwrap(store.memo(id: voiceID))
            XCTAssertNil(written.projectID)
            XCTAssertNil(voice.projectID)
            XCTAssertEqual(written.day, day)
            XCTAssertEqual(voice.day, day)
            XCTAssertEqual(written.photoIDs, [photoID])
            XCTAssertEqual(voice.text, "Installed transcript")
            XCTAssertEqual(voice.title, "Installed voice title")
            XCTAssertTrue(voice.stoppedAtCap)
            XCTAssertEqual(store.photoData(forPhotoID: photoID), photoBytes)
            XCTAssertEqual(store.audioData(forMemoID: voiceID), audioBytes)
        }
        do {
            let reopened = try KyoModelContainer.make(storeURL: url)
            let store = MemoStore(modelContainer: reopened)
            XCTAssertEqual(store.memo(id: writtenID)?.text, "Installed written memo")
            XCTAssertEqual(store.photoData(forPhotoID: photoID), photoBytes)
            XCTAssertEqual(store.audioData(forMemoID: voiceID), audioBytes)
            let projects = ProjectListStore(modelContainer: reopened,
                taskList: TaskListStore(modelContainer: reopened), memoStore: store)
            projectID = try XCTUnwrap(projects.createProject(name: "Kyo")).id
            _ = store.assignMemo(id: writtenID, to: projectID)
            _ = store.assignMemo(id: voiceID, to: projectID)
        }
        let reopened = try KyoModelContainer.make(storeURL: url)
        let store = MemoStore(modelContainer: reopened)
        XCTAssertEqual(Set(store.memos(in: try XCTUnwrap(projectID)).map(\.id)), [writtenID, voiceID])
        XCTAssertEqual(store.memo(id: voiceID)?.createdAt, createdAt)
        XCTAssertEqual(store.memo(id: voiceID)?.day, day)
        XCTAssertEqual(store.photoData(forPhotoID: photoID), photoBytes)
        XCTAssertEqual(store.audioData(forMemoID: voiceID), audioBytes)
    }

    func testInstalledV5ProjectContentMigratesArchivesAndReopensWithExternalMedia() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let project = Project(id: UUID(), name: "Installed project", creationOrder: 2)
        let task = DailyTask(text: "Retained task", creationOrder: 3, projectID: project.id)
        let memoID = UUID()
        let photoID = UUID()
        let day = TaskCompletionDay(era: 1, year: 2026, month: 10, day: 12)
        let bytes = Data(repeating: 4, count: 150_000)
        do {
            let schema = Schema(versionedSchema: KyoSchemaV5.self)
            let installed = try ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            installed.mainContext.insert(PreArchiveProjectSchema.ProjectRecord(project: project))
            installed.mainContext.insert(TaskRecord(task: task))
            SwiftDataHabitContent(modelContainer: installed).save([Habit(name: "Stretch", order: 0)])
            let memo = MemoRecord(id: memoID, kind: .voice, createdAt: .distantPast,
                day: day, text: "Installed transcript", durationSeconds: 4, transcriptState: .transcribed)
            memo.projectID = project.id
            memo.audio = MemoAudioRecord(data: bytes)
            memo.photos = [MemoPhotoRecord(id: photoID, order: 0, data: bytes, thumbnail: Data([1]))]
            installed.mainContext.insert(memo)
            try installed.mainContext.save()
        }
        for opening in 0..<3 {
            let container = try KyoModelContainer.make(storeURL: url)
            let tasks = TaskListStore(modelContainer: container)
            let memos = MemoStore(modelContainer: container)
            let projects = ProjectListStore(modelContainer: container, taskList: tasks, memoStore: memos)
            XCTAssertEqual(projects.projects.first?.isArchived, opening > 0)
            XCTAssertEqual(tasks.tasks(in: project.id), [task])
            XCTAssertEqual(SwiftDataHabitContent(modelContainer: container).load().map(\.name), ["Stretch"])
            XCTAssertEqual(memos.memo(id: memoID)?.projectID, project.id)
            XCTAssertEqual(memos.memo(id: memoID)?.day, day)
            XCTAssertEqual(memos.audioData(forMemoID: memoID), bytes)
            XCTAssertEqual(memos.photoData(forPhotoID: photoID), bytes)
            if opening == 0 { XCTAssertNotNil(projects.archiveProject(id: project.id)) }
            XCTAssertTrue(tasks.tasks.isEmpty)
        }
    }

    func testTheMigrationPlanOnlyAddsModels() {
        XCTAssertEqual(KyoMigrationPlan.schemas.count, 6)
        XCTAssertEqual(KyoMigrationPlan.stages.count, 5)
        let v1 = Set(KyoSchemaV1.models.map { String(describing: $0) })
        let v2 = Set(KyoSchemaV2.models.map { String(describing: $0) })
        XCTAssertTrue(v1.isSubset(of: v2))
        XCTAssertEqual(v2.subtracting(v1), ["MemoRecord", "MemoAudioRecord", "MemoPhotoRecord"])
    }
}
