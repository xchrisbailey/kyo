import SwiftData
import XCTest

/// Behavior tests for #14 (Watch-originated adds/toggles), through the same
/// `TaskListBehavior` surface `TaskListSyncTests` uses. See
/// docs/adr/0002-watch-commands-and-phone-reconciliation.md for the command/outbox/ack/
/// tombstone design these exercise.
@MainActor
final class WatchOriginatedSyncTests: XCTestCase {
    func testWatchAddAppearsOnPhoneWithSameIdAndOrder() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        _ = try XCTUnwrap(phone.addTask(text: "Phone task"))
        let watchTask = try XCTUnwrap(watch.addTask(text: "Watch task"))

        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(phone.tasks.map(\.text), ["Phone task", "Watch task"])
        XCTAssertTrue(phone.tasks.contains { $0.id == watchTask.id })
        // The phone serializes the Watch add after its own, so both sides converge on the
        // phone's creation order.
        let phoneTask = try XCTUnwrap(phone.tasks.first { $0.id == watchTask.id })
        XCTAssertEqual(phoneTask.creationOrder, phone.tasks.first?.creationOrder.advanced(by: 1))
    }

    func testBlankWatchAddCreatesNothingAnywhere() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        XCTAssertNil(watch.addTask(text: "   "))

        XCTAssertTrue(watch.tasks.isEmpty)
        XCTAssertTrue(phone.tasks.isEmpty)
    }

    func testWatchCompleteAndReopenConvergesWithGroupingOrderAndCounts() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        _ = try XCTUnwrap(phone.addTask(text: "First"))
        let second = try XCTUnwrap(phone.addTask(text: "Second"))
        _ = try XCTUnwrap(phone.addTask(text: "Third"))

        _ = watch.toggleTask(id: second.id)
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(watch.tasks.map(\.text), ["First", "Third", "Second"])
        XCTAssertEqual(watch.completedCount, 1)
        XCTAssertEqual(watch.incompleteCount, 2)
        XCTAssertEqual(phone.completedCount, 1)

        _ = watch.toggleTask(id: second.id)
        XCTAssertEqual(watch.tasks, phone.tasks)
        // Reopening restores original creation-order position, ahead of Third.
        XCTAssertEqual(watch.tasks.map(\.text), ["First", "Second", "Third"])
        XCTAssertEqual(watch.completedCount, 0)
    }

    func testWatchChangesPersistAcrossRestartIncludingUnsentOutboxAndDeliverAfterRestart() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watchDefaults = try makeDefaults()
        let watch = try makeWatch(defaults: watchDefaults, transport: transport)

        transport.disconnect()
        let added = try XCTUnwrap(watch.addTask(text: "Offline add"))
        XCTAssertTrue(watch.tasks.contains { $0.id == added.id })
        XCTAssertTrue(phone.tasks.isEmpty)

        // Restart the Watch store against the same defaults without redelivering anything yet;
        // the unsent outbox entry must survive.
        let restartedTransport = ControllableTaskTransport()
        let restartedWatch = try makeWatch(defaults: watchDefaults, transport: restartedTransport)
        XCTAssertTrue(restartedWatch.tasks.contains { $0.id == added.id })

        // On restart the store resends its outbox as a retry; wiring that transport to the
        // phone now delivers it.
        let phone2Transport = ControllableTaskTransport()
        let phone2 = try makePhone(transport: phone2Transport)
        for command in restartedTransport.sentCommands {
            phone2Transport.send(command)
        }
        XCTAssertTrue(phone2.tasks.contains { $0.id == added.id })
    }

    func testOfflineWatchAddsAndTogglesSyncAfterReconnect() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let existing = try XCTUnwrap(phone.addTask(text: "Existing"))
        XCTAssertEqual(watch.tasks, phone.tasks)

        transport.disconnect()
        let added = try XCTUnwrap(watch.addTask(text: "Added offline"))
        _ = watch.toggleTask(id: existing.id)

        XCTAssertTrue(phone.tasks.allSatisfy { $0.id != added.id })
        XCTAssertFalse(try XCTUnwrap(phone.tasks.first { $0.id == existing.id }).isComplete)

        transport.reconnect()

        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertTrue(phone.tasks.contains { $0.id == added.id })
        XCTAssertTrue(try XCTUnwrap(phone.tasks.first { $0.id == existing.id }).isComplete)
    }

    func testDuplicateCommandDeliveryDoesNotDuplicateOrReapplyStaleState() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let added = try XCTUnwrap(watch.addTask(text: "Once"))
        _ = watch.toggleTask(id: added.id)
        _ = watch.toggleTask(id: added.id) // reopened again; final state is incomplete

        guard let addCommand = transport.sentCommands.first else {
            return XCTFail("expected a sent add command")
        }
        transport.redeliver(addCommand)
        transport.redeliver(addCommand)
        transport.redeliver(addCommand)

        XCTAssertEqual(phone.tasks.filter { $0.id == added.id }.count, 1)
        XCTAssertFalse(try XCTUnwrap(phone.tasks.first { $0.id == added.id }).isComplete)
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    func testPhoneDeletionIsNotUndoneByLateOrDuplicateWatchCommand() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let added = try XCTUnwrap(watch.addTask(text: "Doomed"))
        XCTAssertTrue(phone.tasks.contains { $0.id == added.id })

        guard let addCommand = transport.sentCommands.first(where: { command in
            if case .add(let taskID, _) = command.action { return taskID == added.id }
            return false
        }) else {
            return XCTFail("expected an add command for the Watch task")
        }

        _ = phone.deleteTask(id: added.id)
        XCTAssertFalse(phone.tasks.contains { $0.id == added.id })

        // A duplicate delivery of the (now stale) add command must not resurrect the task.
        transport.redeliver(addCommand)
        XCTAssertFalse(phone.tasks.contains { $0.id == added.id })
        XCTAssertFalse(watch.tasks.contains { $0.id == added.id })

        // Nor may a late toggle for the deleted task.
        let toggleCommand = TaskCommand(id: UUID(), action: .setCompletion(taskID: added.id, isComplete: true, completedOn: nil))
        transport.redeliver(toggleCommand)
        XCTAssertFalse(phone.tasks.contains { $0.id == added.id })
    }

    /// A genuine overlap: the Watch is disconnected and acts on stale state (it never saw the
    /// phone's own concurrent changes), so its commands are queued and only reach the phone at
    /// reconnect — strictly after the phone's own disconnected-window changes. Per the
    /// reconciliation rule (docs/adr/0002), the phone applies its own changes and Watch
    /// commands in the order it performs/receives them, so the Watch's commands, arriving
    /// last, win.
    func testOverlappingDisconnectedWatchAndPhoneChangesConvergeWithWatchCommandsWinningAfterReconnect() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watchDefaults = try makeDefaults()
        let watch = try makeWatch(defaults: watchDefaults, transport: transport)

        let t = try XCTUnwrap(phone.addTask(text: "T"))
        let u = try XCTUnwrap(phone.addTask(text: "U"))
        XCTAssertEqual(watch.tasks, phone.tasks)

        transport.disconnect()

        // T: phone completes it, and the Watch — still seeing its pre-disconnect incomplete
        // state — completes it too. Same resulting value, but still exercises command ordering.
        _ = phone.toggleTask(id: t.id)
        _ = watch.toggleTask(id: t.id)

        // U: the phone completes then reopens it (its own net disconnected-window result is
        // "reopened"/incomplete), while the Watch — still seeing U incomplete from before the
        // disconnect — completes it. These are genuinely opposite outcomes.
        _ = phone.toggleTask(id: u.id)
        _ = phone.toggleTask(id: u.id)
        _ = watch.toggleTask(id: u.id)

        // Confirm the divergence is real before reconnecting: the Watch is still working off
        // stale state and disagrees with the phone on U (the phone reopened it locally; the
        // Watch's queued command says complete).
        XCTAssertNotEqual(watch.tasks, phone.tasks)
        XCTAssertFalse(try XCTUnwrap(phone.tasks.first { $0.id == u.id }).isComplete)

        transport.reconnect()

        // The Watch's commands are applied after the phone's own disconnected-window changes,
        // so the Watch's absolute completion states win for both tasks.
        let phoneT = try XCTUnwrap(phone.tasks.first { $0.id == t.id })
        let watchT = try XCTUnwrap(watch.tasks.first { $0.id == t.id })
        XCTAssertTrue(phoneT.isComplete)
        XCTAssertEqual(phoneT, watchT)

        let phoneU = try XCTUnwrap(phone.tasks.first { $0.id == u.id })
        let watchU = try XCTUnwrap(watch.tasks.first { $0.id == u.id })
        XCTAssertTrue(phoneU.isComplete, "the Watch's command should override the phone's own reopened state")
        XCTAssertEqual(phoneU, watchU)

        XCTAssertEqual(watch.tasks, phone.tasks)

        // The Watch's outbox must be fully drained: restarting it against the same storage with
        // a transport that never talks to the phone should show exactly the converged list
        // above, entirely from persisted `baseTasks` with no outbox replay needed.
        let restartedWatch = try makeWatch(defaults: watchDefaults, transport: ControllableTaskTransport())
        XCTAssertEqual(restartedWatch.tasks, phone.tasks)
    }

    /// The mirror image of the above, without any disconnection: the Watch's command reaches
    /// the phone first, and only afterward does the phone change the same task locally. Per the
    /// reconciliation rule, the phone's own later change wins on both devices.
    func testWatchCommandThenLaterPhoneChangeOfSameTaskPhoneChangeWinsOnBothDevices() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let shared = try XCTUnwrap(phone.addTask(text: "Shared"))
        XCTAssertEqual(watch.tasks, phone.tasks)

        _ = watch.toggleTask(id: shared.id)
        XCTAssertTrue(try XCTUnwrap(phone.tasks.first { $0.id == shared.id }).isComplete)

        _ = phone.toggleTask(id: shared.id)

        let phoneResult = try XCTUnwrap(phone.tasks.first { $0.id == shared.id })
        let watchResult = try XCTUnwrap(watch.tasks.first { $0.id == shared.id })
        XCTAssertFalse(phoneResult.isComplete, "the phone's later change should win over the earlier Watch command")
        XCTAssertEqual(phoneResult, watchResult)
        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    /// A disconnected Watch toggles a task the phone deletes in the same window. Deletion is
    /// final: the late-arriving toggle command must not resurrect or otherwise re-add the task.
    func testWatchDisconnectedToggleAndPhoneDeleteOfSameTaskConvergesToDeletedEverywhere() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watchDefaults = try makeDefaults()
        let watch = try makeWatch(defaults: watchDefaults, transport: transport)

        let t = try XCTUnwrap(phone.addTask(text: "T"))
        XCTAssertEqual(watch.tasks, phone.tasks)

        transport.disconnect()
        _ = watch.toggleTask(id: t.id)
        _ = phone.deleteTask(id: t.id)

        transport.reconnect()

        XCTAssertFalse(phone.tasks.contains { $0.id == t.id })
        XCTAssertFalse(watch.tasks.contains { $0.id == t.id })
        XCTAssertEqual(watch.tasks, phone.tasks)

        let restartedWatch = try makeWatch(defaults: watchDefaults, transport: ControllableTaskTransport())
        XCTAssertFalse(restartedWatch.tasks.contains { $0.id == t.id })
    }

    /// The phone's tombstone set and processed-command-id set must survive a phone restart:
    /// a stale add for an already-deleted task must not resurrect it, and a stale completion
    /// command for a task the phone has since changed locally must not be reapplied, even when
    /// both commands were originally applied before the restart.
    func testTombstonesAndProcessedCommandIDsSurvivePhoneRestart() throws {
        let transport = ControllableTaskTransport()
        let phoneDefaults = try makeDefaults()
        let phoneContainer = try KyoModelContainer.make(inMemory: true)
        let phone = try makePhone(defaults: phoneDefaults, container: phoneContainer, transport: transport)
        let watch = try makeWatch(transport: transport)

        let doomed = try XCTUnwrap(watch.addTask(text: "Doomed"))
        XCTAssertTrue(phone.tasks.contains { $0.id == doomed.id })
        let addCommand = try XCTUnwrap(transport.sentCommands.first { command in
            if case .add(let taskID, _) = command.action { return taskID == doomed.id }
            return false
        })
        _ = phone.deleteTask(id: doomed.id)
        XCTAssertFalse(phone.tasks.contains { $0.id == doomed.id })

        let survivor = try XCTUnwrap(watch.addTask(text: "Survivor"))
        _ = watch.toggleTask(id: survivor.id)
        let staleCompletionCommand = try XCTUnwrap(transport.sentCommands.first { command in
            if case .setCompletion(let taskID, _, _) = command.action { return taskID == survivor.id }
            return false
        })
        XCTAssertTrue(try XCTUnwrap(phone.tasks.first { $0.id == survivor.id }).isComplete)
        // A later phone change supersedes the command above.
        _ = phone.toggleTask(id: survivor.id)
        XCTAssertFalse(try XCTUnwrap(phone.tasks.first { $0.id == survivor.id }).isComplete)

        // Restart the phone against the same UserDefaults suite (persisted savedTasks,
        // tombstones, and processed-command ids), wired to a fresh transport.
        let restartedTransport = ControllableTaskTransport()
        let restartedPhone = try makePhone(defaults: phoneDefaults, container: phoneContainer, transport: restartedTransport)

        restartedTransport.send(addCommand)
        XCTAssertFalse(restartedPhone.tasks.contains { $0.id == doomed.id })

        restartedTransport.send(staleCompletionCommand)
        XCTAssertFalse(try XCTUnwrap(restartedPhone.tasks.first { $0.id == survivor.id }).isComplete)
    }

    func testConcurrentPhoneAddAndOfflineWatchAddBothSurviveAndOrderConvergesIdenticallyOnBothDevices() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        transport.disconnect()
        let phoneAdded = try XCTUnwrap(phone.addTask(text: "From phone"))
        let watchAdded = try XCTUnwrap(watch.addTask(text: "From watch"))

        transport.reconnect()

        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertTrue(phone.tasks.contains { $0.id == phoneAdded.id })
        XCTAssertTrue(phone.tasks.contains { $0.id == watchAdded.id })
        XCTAssertEqual(watch.tasks.map(\.id), phone.tasks.map(\.id))
    }

    func testWatchToggleHonorsWatchsDayForCompletionDayRetentionAndRollover() throws {
        let calendar = Calendar(identifier: .gregorian)
        var phoneNow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 12)))
        var watchNow = phoneNow
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport, now: { phoneNow }, calendar: calendar)
        let watch = try makeWatch(transport: transport, now: { watchNow }, calendar: calendar)

        let task = try XCTUnwrap(phone.addTask(text: "Task"))
        _ = watch.toggleTask(id: task.id)
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertTrue(try XCTUnwrap(watch.tasks.first).isComplete)

        // Advance both clocks past midnight without any new sync traffic; the task was
        // completed on the Watch's day, so it should roll off both lists identically.
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 0, minute: 5)))
        phoneNow = nextDay
        watchNow = nextDay
        watch.refreshForCurrentDay()
        phone.refreshForCurrentDay()

        XCTAssertTrue(watch.tasks.isEmpty)
        XCTAssertTrue(phone.tasks.isEmpty)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WatchOriginatedSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePhone(
        defaults: UserDefaults? = nil,
        container: ModelContainer? = nil,
        transport: any TaskSnapshotTransport,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> TaskListStore {
        TaskListStore(
            userDefaults: try defaults ?? makeDefaults(),
            storageKey: "phone",
            modelContainer: try container ?? KyoModelContainer.make(inMemory: true),
            now: now,
            calendar: calendar,
            sync: .publish(to: transport)
        )
    }

    private func makeWatch(
        defaults: UserDefaults? = nil,
        transport: any TaskSnapshotTransport,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> TaskListStore {
        TaskListStore(
            userDefaults: try defaults ?? makeDefaults(),
            storageKey: "watch",
            now: now,
            calendar: calendar,
            sync: .mirror(from: transport)
        )
    }
}
