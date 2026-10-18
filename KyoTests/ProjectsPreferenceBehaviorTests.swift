import SwiftData
import XCTest

@MainActor
final class ProjectsPreferenceBehaviorTests: XCTestCase {
    func testFreshDefaultIsOffAndExplicitChoiceSurvivesReopeningAndUpgrade() throws {
        let suite = "kyo.projectsPreference.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference: any ProjectsPreferenceBehavior = ProjectsPreferenceStore(defaults: defaults)
        XCTAssertFalse(preference.isEnabled)
        preference.setEnabled(true)
        XCTAssertTrue(ProjectsPreferenceStore(defaults: defaults).isEnabled)
        preference.setEnabled(false)
        XCTAssertFalse(ProjectsPreferenceStore(defaults: defaults, hasExistingProjects: true).isEnabled)
    }
    func testDisabledProjectsKeepsChosenTasksInTasksAndLeavesUnscheduledWorkHeld() throws {
        let suite = "kyo.projectsPresentation.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try KyoModelContainer.make(inMemory: true)
        let tasks = TaskListStore(userDefaults: defaults, modelContainer: container)
        let projects = ProjectListStore(modelContainer: container, taskList: tasks)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let everyday = try XCTUnwrap(tasks.addTask(text: "Everyday"))
        let chosen = try XCTUnwrap(projects.addTaskForToday(text: "Chosen", to: project.id))
        let held = try XCTUnwrap(projects.addTask(text: "Held", to: project.id))
        let behavior: any TaskListBehavior = tasks
        XCTAssertEqual(behavior.tasksSection(projectsEnabled: false).map(\.id), [everyday.id, chosen.id])
        XCTAssertEqual(behavior.tasksSection(projectsEnabled: true).map(\.id), [everyday.id])
        XCTAssertEqual(behavior.projectSections(projectsEnabled: false), [])
        XCTAssertEqual(behavior.projectSections(projectsEnabled: true).map(\.id), [project.id])
        _ = tasks.toggleTask(id: chosen.id)
        XCTAssertEqual(behavior.projectSections(projectsEnabled: true).map(\.id), [project.id])
        XCTAssertEqual(behavior.tasksSection(projectsEnabled: false).count, 2)
        XCTAssertEqual(tasks.tasks(in: project.id).first { $0.id == held.id }, held)
        XCTAssertEqual(tasks.taskCount, 2)
    }
    func testMigrationEnablesActiveAndArchivedProjectUsersButFreshDefaultDoesNotPublish() throws {
        for hasProjects in [false, true] {
            let suite = "kyo.projectsUpgrade.tests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let cloud = ControllableProjectsPreferenceCloud()
            let preference = ProjectsPreferenceStore(defaults: defaults, hasExistingProjects: hasProjects, cloud: cloud)
            XCTAssertEqual(preference.isEnabled, hasProjects)
            XCTAssertEqual(cloud.data != nil, hasProjects)
        }
    }

    func testExplicitOffConvergesOverUpgradeOnAndStaleDeliveryRepairsTheCloud() throws {
        let phoneSuite = "kyo.projectsPhone.tests.\(UUID().uuidString)"
        let padSuite = "kyo.projectsPad.tests.\(UUID().uuidString)"
        let phoneDefaults = try XCTUnwrap(UserDefaults(suiteName: phoneSuite))
        let padDefaults = try XCTUnwrap(UserDefaults(suiteName: padSuite))
        defer {
            phoneDefaults.removePersistentDomain(forName: phoneSuite)
            padDefaults.removePersistentDomain(forName: padSuite)
        }
        let phoneCloud = ControllableProjectsPreferenceCloud()
        let padCloud = ControllableProjectsPreferenceCloud()
        let phone = ProjectsPreferenceStore(defaults: phoneDefaults, hasExistingProjects: true,
            cloud: phoneCloud, now: { Date(timeIntervalSince1970: 500) })
        let inferred = try XCTUnwrap(phoneCloud.data)
        let pad = ProjectsPreferenceStore(defaults: padDefaults, cloud: padCloud,
            now: { Date(timeIntervalSince1970: 100) })
        pad.setEnabled(false)
        let explicit = try XCTUnwrap(padCloud.data)
        phoneCloud.deliver(explicit)
        XCTAssertFalse(phone.isEnabled, "an older-clock explicit choice still outranks migration")
        phoneCloud.deliver(inferred)
        XCTAssertFalse(phone.isEnabled)
        XCTAssertEqual(try decode(phoneCloud.data), try decode(explicit), "the local winner repairs stale cloud state")
        padCloud.deliver(inferred)
        XCTAssertFalse(pad.isEnabled)
        XCTAssertEqual(try decode(padCloud.data), try decode(explicit))
        XCTAssertFalse(ProjectsPreferenceStore(defaults: phoneDefaults, hasExistingProjects: true).isEnabled)
        phone.setEnabled(true)
        padCloud.deliver(phoneCloud.data)
        XCTAssertTrue(pad.isEnabled)
    }

    func testConcurrentExplicitChoicesConvergeAndOfflineChoicePersists() throws {
        let suites = (0..<2).map { _ in "kyo.projectsConcurrent.tests.\(UUID().uuidString)" }
        let defaults = try suites.map { try XCTUnwrap(UserDefaults(suiteName: $0)) }
        defer { for (index, suite) in suites.enumerated() { defaults[index].removePersistentDomain(forName: suite) } }
        let clouds = [ControllableProjectsPreferenceCloud(), ControllableProjectsPreferenceCloud()]
        let phone = ProjectsPreferenceStore(defaults: defaults[0], cloud: clouds[0], now: { Date(timeIntervalSince1970: 100) })
        let pad = ProjectsPreferenceStore(defaults: defaults[1], cloud: clouds[1], now: { Date(timeIntervalSince1970: 100) })
        phone.setEnabled(true)
        pad.setEnabled(false)
        let phoneRecord = try XCTUnwrap(clouds[0].data)
        let padRecord = try XCTUnwrap(clouds[1].data)
        clouds[0].deliver(padRecord)
        clouds[1].deliver(phoneRecord)
        XCTAssertEqual(phone.isEnabled, pad.isEnabled)
        XCTAssertEqual(try decode(clouds[0].data), try decode(clouds[1].data))
        XCTAssertEqual(ProjectsPreferenceStore(defaults: defaults[0]).isEnabled, phone.isEnabled)
    }

    func testWatchUsesNewestPhonePreferenceAndRetainsItAcrossMissingContextsAndRestart() throws {
        let suite = "kyo.projectsWatch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = WatchConnectivityTaskTransport(session: nil)
        let watch = WatchProjectsPreferenceStore(defaults: defaults, transport: transport)
        XCTAssertTrue(watch.isEnabled, "a legacy phone keeps project access")
        let newer = WatchProjectsPreference(revision: 20, isEnabled: false)
        transport.receive(.init([WatchConnectivityTaskTransport.projectsPreferenceKey: try JSONEncoder().encode(newer)]))
        XCTAssertFalse(watch.isEnabled)
        transport.receive(.init([:]))
        let stale = WatchProjectsPreference(revision: 10, isEnabled: true)
        transport.receive(.init([WatchConnectivityTaskTransport.projectsPreferenceKey: try JSONEncoder().encode(stale)]))
        XCTAssertFalse(watch.isEnabled)
        XCTAssertFalse(WatchProjectsPreferenceStore(defaults: defaults).isEnabled)
        let lateReceiver = WatchProjectsPreferenceStore(defaults: defaults, transport: transport)
        XCTAssertFalse(lateReceiver.isEnabled)
        lateReceiver.receive(WatchProjectsPreference(revision: 21, isEnabled: true))
        XCTAssertTrue(lateReceiver.isEnabled)
    }
    func testAnArchivedOnlyInstalledStoreEnablesProjectsUnlessExplicitlyDisabled() throws {
        let suite = "kyo.projectsArchivedUpgrade.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try KyoModelContainer.make(inMemory: true)
        let tasks = TaskListStore(userDefaults: defaults, modelContainer: container)
        let projects = ProjectListStore(modelContainer: container, taskList: tasks)
        let project = try XCTUnwrap(projects.createProject(name: "Archived"))
        _ = projects.archiveProject(id: project.id)
        let preference: any ProjectsPreferenceBehavior = ProjectsPreferenceStore(modelContainer: container, defaults: defaults)
        XCTAssertTrue(preference.isEnabled)
        preference.setEnabled(false)
        XCTAssertFalse(ProjectsPreferenceStore(modelContainer: container, defaults: defaults).isEnabled)
    }

    func testPreferenceChangesKeepPendingWatchEditsAndFutureOfflineAvailability() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let suite = "kyo.projectsPendingWatch.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar(identifier: .gregorian)
        var now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let transport = ControllableTaskTransport()
        let phone = TaskListStore(userDefaults: defaults, storageKey: "phone", modelContainer: container,
            now: { now }, calendar: calendar, sync: .publish(to: transport))
        let projects = ProjectListStore(modelContainer: container, taskList: phone)
        let project = try XCTUnwrap(projects.createProject(name: "Kyo"))
        let chosen = try XCTUnwrap(projects.addTaskForToday(text: "Chosen", to: project.id))
        let future = try XCTUnwrap(projects.addTask(text: "Tomorrow", to: project.id, plannedFor: tomorrow))
        let watch = TaskListStore(userDefaults: defaults, storageKey: "watch", now: { now }, calendar: calendar,
            sync: .mirror(from: transport))
        let preference = WatchProjectsPreferenceStore(defaults: defaults)
        transport.disconnect()
        _ = watch.editTask(id: chosen.id, text: "Edited offline")
        _ = watch.toggleTask(id: chosen.id)
        preference.receive(WatchProjectsPreference(revision: 10, isEnabled: false))
        XCTAssertEqual(watch.tasksSection(projectsEnabled: preference.isEnabled).map(\.text), ["Edited offline"])
        XCTAssertTrue(watch.projectSections(projectsEnabled: preference.isEnabled).isEmpty)
        transport.reconnect()
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(phone.tasks.first?.projectID, project.id)
        XCTAssertTrue(try XCTUnwrap(phone.tasks.first).isComplete)
        transport.disconnect()
        now = tomorrow
        watch.refreshForCurrentDay()
        XCTAssertEqual(watch.tasksSection(projectsEnabled: preference.isEnabled).map(\.id), [future.id])
        preference.receive(WatchProjectsPreference(revision: 11, isEnabled: true))
        XCTAssertEqual(watch.projectSections(projectsEnabled: preference.isEnabled).map(\.id), [project.id])
        XCTAssertTrue(watch.tasksSection(projectsEnabled: preference.isEnabled).isEmpty)
    }

    func testACloudExplicitChoiceArrivingBeforeUpgradeInferenceIsRetained() throws {
        let suite = "kyo.projectsCloudUpgrade.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = ControllableProjectsPreferenceCloud()
        let explicitOff = ProjectsPreferenceRecord(version: 1, isEnabled: false, isExplicit: true,
            timestamp: 1, deviceID: "other-device", recordID: "choice")
        cloud.deliver(try JSONEncoder().encode(explicitOff))
        let preference = ProjectsPreferenceStore(defaults: defaults, hasExistingProjects: true, cloud: cloud)
        XCTAssertFalse(preference.isEnabled)
        XCTAssertEqual(try decode(cloud.data), explicitOff)
    }

    func testProjectsPreferenceSharesTheSameContextWithTasksHabitsMemosAndTheme() throws {
        let transport = WatchConnectivityTaskTransport(session: nil)
        transport.publish(themeID: "neko")
        transport.publish(projectsPreference: WatchProjectsPreference(revision: 30, isEnabled: false))
        XCTAssertNil(transport.contextToWrite, "preferences alone must not replace missing task content")
        transport.publish(TaskListSnapshot(revision: 1, tasks: []))
        transport.publishContextEntry(Data([1]), forKey: WatchConnectivityTaskTransport.habitSnapshotKey)
        transport.publishContextEntry(Data([2]), forKey: WatchConnectivityTaskTransport.memoSnapshotKey)
        let context = try XCTUnwrap(transport.contextToWrite)
        XCTAssertEqual(Set(context.keys), Set([WatchConnectivityTaskTransport.snapshotKey,
            WatchConnectivityTaskTransport.habitSnapshotKey, WatchConnectivityTaskTransport.memoSnapshotKey,
            WatchConnectivityTaskTransport.themeIDKey, WatchConnectivityTaskTransport.projectsPreferenceKey]))
        let decoded = WatchConnectivityTaskTransport.ReceivedContext(context)
        XCTAssertEqual(decoded.projectsPreference, WatchProjectsPreference(revision: 30, isEnabled: false))
        XCTAssertEqual(decoded.themeID, "neko")
    }

    func testUserChoiceAdvancesBeyondCachedRemoteRecordBeforeItsNotificationArrives() throws {
        let suite = "kyo.projectsCachedRemote.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = ControllableProjectsPreferenceCloud()
        let preference = ProjectsPreferenceStore(defaults: defaults, cloud: cloud,
            now: { Date(timeIntervalSince1970: 100) })
        preference.setEnabled(false)
        let remote = ProjectsPreferenceRecord(version: 1, isEnabled: false, isExplicit: true,
            timestamp: 500_000, deviceID: "peer", recordID: "remote-off")
        cloud.write(try JSONEncoder().encode(remote)) // cached by iCloud, notification still pending
        preference.setEnabled(true)
        XCTAssertTrue(preference.isEnabled)
        let published = try decode(cloud.data)
        XCTAssertTrue(published.isEnabled)
        XCTAssertGreaterThan(published.timestamp, 500_000)
        XCTAssertTrue(ProjectsPreferenceStore(defaults: defaults).isEnabled)
    }

    private func decode(_ data: Data?) throws -> ProjectsPreferenceRecord {
        try JSONDecoder().decode(ProjectsPreferenceRecord.self, from: XCTUnwrap(data))
    }
}
