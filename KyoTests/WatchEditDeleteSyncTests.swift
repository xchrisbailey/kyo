import SwiftData
import XCTest

/// Behavior tests for #21 (Watch edit and delete), through the same `TaskListBehavior` surface
/// `WatchOriginatedSyncTests` uses. See the "#21" section of
/// docs/adr/0002-watch-commands-and-phone-reconciliation.md for the rename/delete commands and
/// the delete-wins rule these exercise.
@MainActor
final class WatchEditDeleteSyncTests: XCTestCase {
    func testWatchRenameAppearsOnPhoneKeepingOrderGroupingAndCompletion() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        _ = try XCTUnwrap(phone.addTask(text: "First"))
        let second = try XCTUnwrap(phone.addTask(text: "Second"))
        let third = try XCTUnwrap(phone.addTask(text: "Third"))
        _ = phone.toggleTask(id: third.id)

        let renamed = try XCTUnwrap(watch.editTask(id: second.id, text: "  Second, renamed \n"))
        XCTAssertEqual(renamed.text, "Second, renamed")
        XCTAssertEqual(renamed.creationOrder, second.creationOrder)

        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(phone.tasks.map(\.text), ["First", "Second, renamed", "Third"])
        XCTAssertEqual(phone.tasks.map(\.isComplete), [false, false, true])
        XCTAssertEqual(phone.completedCount, 1)
    }

    func testWatchRenameOfCompletedTaskKeepsItCompleted() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let task = try XCTUnwrap(phone.addTask(text: "Done"))
        _ = watch.toggleTask(id: task.id)
        let completed = try XCTUnwrap(phone.tasks.first)
        XCTAssertTrue(completed.isComplete)

        _ = try XCTUnwrap(watch.editTask(id: task.id, text: "Done, renamed"))

        let phoneTask = try XCTUnwrap(phone.tasks.first)
        XCTAssertEqual(phoneTask.text, "Done, renamed")
        XCTAssertTrue(phoneTask.isComplete)
        XCTAssertEqual(phoneTask.completedOn, completed.completedOn)
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    func testBlankWatchRenameDoesNothingOnEitherDevice() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let task = try XCTUnwrap(phone.addTask(text: "Keep me"))
        let sentBefore = transport.sentCommands.count

        XCTAssertNil(watch.editTask(id: task.id, text: " \n\t "))

        XCTAssertEqual(transport.sentCommands.count, sentBefore)
        XCTAssertEqual(watch.tasks.map(\.text), ["Keep me"])
        XCTAssertEqual(phone.tasks.map(\.text), ["Keep me"])
    }

    func testWatchDeleteRemovesTaskOnBothDevices() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let first = try XCTUnwrap(phone.addTask(text: "First"))
        _ = try XCTUnwrap(phone.addTask(text: "Second"))

        let removed = try XCTUnwrap(watch.deleteTask(id: first.id))

        XCTAssertEqual(removed.id, first.id)
        XCTAssertEqual(watch.tasks.map(\.text), ["Second"])
        XCTAssertEqual(phone.tasks.map(\.text), ["Second"])
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    func testWatchDeleteOfCompletedTaskWorks() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let task = try XCTUnwrap(phone.addTask(text: "Done"))
        _ = watch.toggleTask(id: task.id)
        XCTAssertEqual(phone.completedCount, 1)

        let removed = try XCTUnwrap(watch.deleteTask(id: task.id))

        XCTAssertTrue(removed.isComplete)
        XCTAssertTrue(watch.tasks.isEmpty)
        XCTAssertTrue(phone.tasks.isEmpty)
    }

    func testOfflineWatchRenameAndDeletePersistAcrossWatchRestartThenSyncAfterReconnect() throws {
        let transport = ControllableTaskTransport()
        let phoneDefaults = try makeDefaults()
        let phoneContainer = try KyoModelContainer.make(inMemory: true)
        let phone = try makePhone(defaults: phoneDefaults, container: phoneContainer, transport: transport)
        let watchDefaults = try makeDefaults()
        let watch = try makeWatch(defaults: watchDefaults, transport: transport)

        let renamedTask = try XCTUnwrap(phone.addTask(text: "Rename me"))
        let deletedTask = try XCTUnwrap(phone.addTask(text: "Delete me"))

        transport.disconnect()
        _ = try XCTUnwrap(watch.editTask(id: renamedTask.id, text: "Renamed offline"))
        _ = try XCTUnwrap(watch.deleteTask(id: deletedTask.id))
        XCTAssertEqual(phone.tasks.map(\.text), ["Rename me", "Delete me"])

        // Restart the Watch offline: the unsent outbox must survive and still shape the list.
        let offlineWatch = try makeWatch(defaults: watchDefaults, transport: ControllableTaskTransport())
        XCTAssertEqual(offlineWatch.tasks.map(\.text), ["Renamed offline"])

        // Reconnect with both devices on a fresh shared transport; the Watch resends its outbox.
        let newTransport = ControllableTaskTransport()
        let restartedPhone = try makePhone(defaults: phoneDefaults, container: phoneContainer, transport: newTransport)
        let restartedWatch = try makeWatch(defaults: watchDefaults, transport: newTransport)

        XCTAssertEqual(restartedPhone.tasks.map(\.text), ["Renamed offline"])
        XCTAssertEqual(restartedWatch.tasks, restartedPhone.tasks)
    }

    func testDuplicateRenameAndDeleteDeliveryIsHarmless() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let renamedTask = try XCTUnwrap(phone.addTask(text: "Rename me"))
        let deletedTask = try XCTUnwrap(phone.addTask(text: "Delete me"))
        _ = watch.editTask(id: renamedTask.id, text: "Renamed")
        _ = watch.deleteTask(id: deletedTask.id)
        let renameCommand = try XCTUnwrap(transport.sentCommands.first)
        let deleteCommand = try XCTUnwrap(transport.sentCommands.last)

        // The phone renames again afterward; a stale duplicate of the Watch rename must not
        // undo that.
        _ = phone.editTask(id: renamedTask.id, text: "Phone's final")
        transport.redeliver(renameCommand)
        transport.redeliver(deleteCommand)
        transport.redeliver(deleteCommand)

        XCTAssertEqual(phone.tasks.map(\.text), ["Phone's final"])
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    // MARK: - Conflicting renames

    func testDisconnectedPhoneRenameThenWatchRenameWatchWinsAfterReconnect() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let task = try XCTUnwrap(phone.addTask(text: "Original"))

        transport.disconnect()
        _ = phone.editTask(id: task.id, text: "Phone rename")
        _ = watch.editTask(id: task.id, text: "Watch rename")
        XCTAssertEqual(phone.tasks.map(\.text), ["Phone rename"])
        XCTAssertEqual(watch.tasks.map(\.text), ["Watch rename"])

        transport.reconnect()

        XCTAssertEqual(phone.tasks.map(\.text), ["Watch rename"])
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    func testWatchRenameDeliveredThenPhoneRenamePhoneWins() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let task = try XCTUnwrap(phone.addTask(text: "Original"))

        _ = watch.editTask(id: task.id, text: "Watch rename")
        XCTAssertEqual(phone.tasks.map(\.text), ["Watch rename"])
        _ = phone.editTask(id: task.id, text: "Phone rename")

        XCTAssertEqual(phone.tasks.map(\.text), ["Phone rename"])
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    // MARK: - Delete wins

    func testWatchDeleteRacingPhoneRenameOrCompletionEndsDeletedInEitherArrivalOrder() throws {
        for phoneChangeFirst in [true, false] {
            for phoneChange in [PhoneChange.rename, .toggle] {
                let transport = ControllableTaskTransport()
                let phoneDefaults = try makeDefaults()
                let phoneContainer = try KyoModelContainer.make(inMemory: true)
                let phone = try makePhone(defaults: phoneDefaults, container: phoneContainer, transport: transport)
                let watchDefaults = try makeDefaults()
                let watch = try makeWatch(defaults: watchDefaults, transport: transport)
                let task = try XCTUnwrap(phone.addTask(text: "Racer"))
                let label = "phoneChangeFirst=\(phoneChangeFirst), \(phoneChange)"

                if phoneChangeFirst {
                    // Disconnected: the phone changes first, and the Watch delete arrives later.
                    transport.disconnect()
                    applyPhoneChange(phoneChange, to: phone, taskID: task.id)
                    _ = watch.deleteTask(id: task.id)
                    transport.reconnect()
                } else {
                    // Connected: the Watch delete lands first, so the phone's change finds nothing.
                    _ = watch.deleteTask(id: task.id)
                    applyPhoneChange(phoneChange, to: phone, taskID: task.id)
                }

                XCTAssertTrue(phone.tasks.isEmpty, label)
                XCTAssertTrue(watch.tasks.isEmpty, label)

                let restartTransport = ControllableTaskTransport()
                let restartedPhone = try makePhone(defaults: phoneDefaults, container: phoneContainer, transport: restartTransport)
                let restartedWatch = try makeWatch(defaults: watchDefaults, transport: restartTransport)
                XCTAssertTrue(restartedPhone.tasks.isEmpty, label)
                XCTAssertTrue(restartedWatch.tasks.isEmpty, label)
            }
        }
    }

    func testPhoneDeleteRacingWatchRenameOrDeleteConvergesToDeleted() throws {
        for watchAction in [WatchChange.rename, .delete] {
            let transport = ControllableTaskTransport()
            let phone = try makePhone(transport: transport)
            let watch = try makeWatch(transport: transport)
            let task = try XCTUnwrap(phone.addTask(text: "Racer"))

            transport.disconnect()
            switch watchAction {
            case .rename: _ = watch.editTask(id: task.id, text: "Watch rename")
            case .delete: _ = watch.deleteTask(id: task.id)
            }
            _ = phone.deleteTask(id: task.id)
            transport.reconnect()

            XCTAssertTrue(phone.tasks.isEmpty, "\(watchAction)")
            XCTAssertTrue(watch.tasks.isEmpty, "\(watchAction)")
        }
    }

    // MARK: - Add then delete before the phone acknowledges the add

    func testWatchAddDeletedBeforePhoneAcksAddEndsDeletedOnBothDevices() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        transport.disconnect()
        let added = try XCTUnwrap(watch.addTask(text: "Fleeting"))
        _ = try XCTUnwrap(watch.deleteTask(id: added.id))
        XCTAssertTrue(watch.tasks.isEmpty)
        let addCommand = try XCTUnwrap(transport.sentCommands.first)

        // A snapshot that contains the task but acknowledges only the add must not bring it back.
        let lastRevision = try XCTUnwrap(transport.published.last).revision
        transport.deliver(TaskListSnapshot(
            revision: lastRevision + 1,
            tasks: [DailyTask(id: added.id, text: "Fleeting", creationOrder: 0)],
            acknowledgedCommandIDs: [addCommand.id]
        ))
        XCTAssertTrue(watch.tasks.isEmpty)

        transport.reconnect()

        XCTAssertTrue(phone.tasks.isEmpty)
        XCTAssertTrue(watch.tasks.isEmpty)
    }

    func testTombstoneFromWatchDeleteSurvivesPhoneRestartAndRedeliveredAdd() throws {
        let transport = ControllableTaskTransport()
        let phoneDefaults = try makeDefaults()
        let phoneContainer = try KyoModelContainer.make(inMemory: true)
        let phone = try makePhone(defaults: phoneDefaults, container: phoneContainer, transport: transport)
        let watch = try makeWatch(transport: transport)

        let added = try XCTUnwrap(watch.addTask(text: "Fleeting"))
        let addCommand = try XCTUnwrap(transport.sentCommands.first)
        _ = try XCTUnwrap(watch.deleteTask(id: added.id))
        XCTAssertTrue(phone.tasks.isEmpty)

        let restartedTransport = ControllableTaskTransport()
        let restartedPhone = try makePhone(defaults: phoneDefaults, container: phoneContainer, transport: restartedTransport)
        restartedTransport.send(TaskCommand(id: UUID(), action: .add(taskID: added.id, text: "Fleeting")))
        restartedTransport.send(addCommand)

        XCTAssertTrue(restartedPhone.tasks.isEmpty)
    }

    func testDeleteOfTaskAlreadyAbsentOnPhoneStillTombstonesIt() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        _ = try makeWatch(transport: transport)

        let unknownID = UUID()
        transport.send(TaskCommand(id: UUID(), action: .delete(taskID: unknownID)))
        transport.send(TaskCommand(id: UUID(), action: .add(taskID: unknownID, text: "Late add")))

        XCTAssertTrue(phone.tasks.isEmpty)
    }

    // MARK: - Unknown ids

    func testWatchEditOrDeleteOfUnknownIdReturnsNilAndSendsNothing() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)
        _ = try XCTUnwrap(phone.addTask(text: "Existing"))

        XCTAssertNil(watch.editTask(id: UUID(), text: "Nope"))
        XCTAssertNil(watch.deleteTask(id: UUID()))

        XCTAssertTrue(transport.sentCommands.isEmpty)
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    // MARK: - Helpers

    private enum PhoneChange { case rename, toggle }
    private enum WatchChange { case rename, delete }

    private func applyPhoneChange(_ change: PhoneChange, to phone: TaskListStore, taskID: UUID) {
        switch change {
        case .rename: _ = phone.editTask(id: taskID, text: "Phone rename")
        case .toggle: _ = phone.toggleTask(id: taskID)
        }
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WatchEditDeleteSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePhone(
        defaults: UserDefaults? = nil,
        container: ModelContainer? = nil,
        transport: any TaskSnapshotTransport
    ) throws -> TaskListStore {
        TaskListStore(
            userDefaults: try defaults ?? makeDefaults(),
            storageKey: "phone",
            modelContainer: try container ?? KyoModelContainer.make(inMemory: true),
            calendar: Calendar(identifier: .gregorian),
            sync: .publish(to: transport)
        )
    }

    private func makeWatch(
        defaults: UserDefaults? = nil,
        transport: any TaskSnapshotTransport
    ) throws -> TaskListStore {
        TaskListStore(
            userDefaults: try defaults ?? makeDefaults(),
            storageKey: "watch",
            calendar: Calendar(identifier: .gregorian),
            sync: .mirror(from: transport)
        )
    }
}
