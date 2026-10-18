import SwiftData
import XCTest

@MainActor
final class ProjectsOptInPersistenceTests: XCTestCase {
    func testDisablingAndReenablingAcrossDiskReopenPreservesContentAndCollapseChoices() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Kyo.store")
        let suite = "kyo.projectsOptInPersistence.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let photo = StoredPhoto(data: Data([1, 2]), thumbnail: Data([3]))
        var project: Project!
        var archived: Project!
        var allTasks: [DailyTask] = []
        var voice: Memo!
        var written: Memo!
        do {
            let container = try KyoModelContainer.make(storeURL: url)
            let tasks = TaskListStore(userDefaults: defaults, modelContainer: container, now: { today }, calendar: calendar)
            let memos = MemoStore(modelContainer: container, now: { today }, calendar: calendar, userDefaults: defaults)
            let projects = ProjectListStore(modelContainer: container, taskList: tasks, memoStore: memos)
            project = try XCTUnwrap(projects.createProject(name: "Kyo"))
            archived = try XCTUnwrap(projects.createProject(name: "House"))
            let chosen = try XCTUnwrap(projects.addTaskForToday(text: "Chosen", to: project.id))
            _ = try XCTUnwrap(projects.addTask(text: "Later", to: project.id, plannedFor: tomorrow))
            _ = try XCTUnwrap(projects.addTask(text: "Held", to: project.id))
            let complete = try XCTUnwrap(projects.addTaskForToday(text: "Done", to: project.id))
            _ = tasks.toggleTask(id: complete.id)
            _ = projects.addTaskForToday(text: "Archived task", to: archived.id)
            archived = try XCTUnwrap(projects.archiveProject(id: archived.id))
            allTasks = tasks.tasks(in: project.id)
            written = try XCTUnwrap(memos.addWrittenMemo(text: "Keep text", photos: [photo], projectID: project.id))
            let audio = RecordedAudio(id: UUID(), startedAt: today, duration: 3, data: Data([4, 5]))
            voice = try memos.saveVoiceMemo(audio, stoppedAtCap: false, photos: [],
                context: RecordingMemoContext(day: TaskCompletionDay(date: today, calendar: calendar), projectID: project.id))
            let sections = CollapsedSections(defaults: defaults)
            sections.toggle(.projects)
            sections.toggleProject(project.id)
            let preference = ProjectsPreferenceStore(defaults: defaults, hasExistingProjects: true)
            XCTAssertTrue(preference.isEnabled)
            preference.setEnabled(false)
            XCTAssertEqual(tasks.tasksSection(projectsEnabled: preference.isEnabled).map(\.id), [chosen.id, complete.id])
            XCTAssertTrue(tasks.projectSections(projectsEnabled: preference.isEnabled).isEmpty)
            XCTAssertEqual(tasks.laterTasks.map(\.text), ["Later"])
            XCTAssertEqual(memos.memos(on: today).count, 2)
        }
        let reopened = try KyoModelContainer.make(storeURL: url)
        let tasks = TaskListStore(userDefaults: defaults, modelContainer: reopened, now: { today }, calendar: calendar)
        let memos = MemoStore(modelContainer: reopened, now: { today }, calendar: calendar, userDefaults: defaults)
        let projects = ProjectListStore(modelContainer: reopened, taskList: tasks, memoStore: memos)
        let preference = ProjectsPreferenceStore(defaults: defaults, hasExistingProjects: true)
        XCTAssertFalse(preference.isEnabled)
        preference.setEnabled(true)
        XCTAssertEqual(projects.projects, [project, archived])
        XCTAssertEqual(tasks.tasks(in: project.id), allTasks)
        XCTAssertEqual(memos.memo(id: written.id), written)
        XCTAssertEqual(memos.memo(id: voice.id), voice)
        XCTAssertEqual(memos.photoData(forPhotoID: photo.id), photo.data)
        XCTAssertEqual(memos.audioData(forMemoID: voice.id), Data([4, 5]))
        XCTAssertTrue(CollapsedSections(defaults: defaults).isCollapsed(.projects))
        XCTAssertTrue(CollapsedSections(defaults: defaults).isProjectCollapsed(project.id))
        XCTAssertEqual(tasks.projectSections(projectsEnabled: preference.isEnabled), [project])
        XCTAssertTrue(tasks.tasksSection(projectsEnabled: preference.isEnabled).isEmpty)
    }

    func testMonthKeepsPlannedAndCompletedRowsWhileLivePreferenceHidesTheirProjectNames() throws {
        let suite = "kyo.projectsMonth.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try KyoModelContainer.make(inMemory: true)
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let tasks = TaskListStore(userDefaults: defaults, modelContainer: container, now: { today }, calendar: calendar)
        let projects = ProjectListStore(modelContainer: container, taskList: tasks)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let done = try XCTUnwrap(projects.addTaskForToday(text: "Done", to: project.id))
        _ = tasks.toggleTask(id: done.id)
        let future = try XCTUnwrap(projects.addTask(text: "Future", to: project.id, plannedFor: tomorrow))
        let preference = ProjectsPreferenceStore(defaults: defaults, hasExistingProjects: true)
        let month = TaskMonthContent(taskList: tasks, projectsPreference: preference)
        XCTAssertEqual(month.content(on: [today])[today]?.rows.first?.projectName, "Kyo")
        preference.setEnabled(false)
        XCTAssertNil(month.content(on: [today])[today]?.rows.first?.projectName)
        XCTAssertNil(month.content(on: [tomorrow])[tomorrow]?.rows.first?.projectName)
        XCTAssertEqual(month.content(on: [today])[today]?.rows.first?.text, "Done")
        XCTAssertEqual(month.content(on: [tomorrow])[tomorrow]?.rows.first?.text, "Future")
        XCTAssertEqual(tasks.laterTasks, [future])
        preference.setEnabled(true)
        XCTAssertEqual(month.content(on: [tomorrow])[tomorrow]?.rows.first?.projectName, "Kyo")
    }
}
