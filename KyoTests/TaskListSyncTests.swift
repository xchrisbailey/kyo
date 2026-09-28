import XCTest

@MainActor
final class TaskListSyncTests: XCTestCase {
    func testWatchShowsPhoneListWithMatchingOrderAndCounts() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        _ = try XCTUnwrap(phone.addTask(text: "First"))
        _ = try XCTUnwrap(phone.addTask(text: "Second"))
        _ = try XCTUnwrap(phone.addTask(text: "Third"))
        let second = try XCTUnwrap(phone.tasks.first { $0.text == "Second" })
        _ = phone.toggleTask(id: second.id)

        XCTAssertEqual(watch.tasks.map(\.text), ["First", "Third", "Second"])
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(watch.completedCount, 1)
        XCTAssertEqual(watch.incompleteCount, 2)
        XCTAssertEqual(watch.taskCount, 3)
    }

    func testPhoneEditsDeletesAndCompletionChangesReachWatch() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let a = try XCTUnwrap(phone.addTask(text: "A"))
        let b = try XCTUnwrap(phone.addTask(text: "B"))
        _ = try XCTUnwrap(phone.addTask(text: "C"))
        XCTAssertEqual(watch.tasks, phone.tasks)

        _ = phone.editTask(id: b.id, text: "B renamed")
        XCTAssertEqual(watch.tasks, phone.tasks)

        _ = phone.toggleTask(id: b.id)
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(watch.tasks.last?.id, b.id)

        _ = phone.toggleTask(id: b.id)
        XCTAssertEqual(watch.tasks, phone.tasks)
        // A reopened task returns to its creation-order position, ahead of C.
        XCTAssertEqual(watch.tasks.map(\.id), [a.id, b.id, phone.tasks[2].id])

        _ = phone.deleteTask(id: a.id)
        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertFalse(watch.tasks.contains { $0.id == a.id })
    }

    func testWatchStartedAfterPhoneChangesShowsLatestList() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)

        let first = try XCTUnwrap(phone.addTask(text: "First"))
        _ = try XCTUnwrap(phone.addTask(text: "Second"))
        _ = phone.toggleTask(id: first.id)

        let watch = try makeWatch(transport: transport)

        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    func testWatchKeepsSyncedTasksAfterRestart() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watchDefaults = try makeDefaults()
        let watch = try makeWatch(defaults: watchDefaults, transport: transport)

        _ = try XCTUnwrap(phone.addTask(text: "First"))
        _ = try XCTUnwrap(phone.addTask(text: "Second"))
        let syncedTasks = watch.tasks
        XCTAssertEqual(syncedTasks, phone.tasks)

        let restartedWatch = try makeWatch(defaults: watchDefaults, transport: ControllableTaskTransport())

        XCTAssertEqual(restartedWatch.tasks, syncedTasks)
    }

    func testWatchCatchesUpAfterReconnecting() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let first = try XCTUnwrap(phone.addTask(text: "First"))
        _ = try XCTUnwrap(phone.addTask(text: "Second"))
        let staleList = watch.tasks

        transport.disconnect()
        _ = phone.addTask(text: "Third")
        _ = phone.editTask(id: first.id, text: "First renamed")
        _ = phone.toggleTask(id: first.id)
        _ = phone.deleteTask(id: first.id)

        XCTAssertEqual(watch.tasks, staleList)

        transport.reconnect()

        XCTAssertEqual(watch.tasks, phone.tasks)
    }

    func testRepeatedDeliveryDoesNotDuplicateTasks() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        let watch = try makeWatch(transport: transport)

        let first = try XCTUnwrap(phone.addTask(text: "First"))
        _ = try XCTUnwrap(phone.addTask(text: "Second"))
        _ = phone.toggleTask(id: first.id)
        _ = phone.addTask(text: "Third")

        for snapshot in transport.published {
            transport.deliver(snapshot)
        }
        if let latest = transport.published.last {
            transport.deliver(latest)
            transport.deliver(latest)
            transport.deliver(latest)
        }

        XCTAssertEqual(watch.tasks, phone.tasks)
        XCTAssertEqual(watch.taskCount, phone.taskCount)
        XCTAssertEqual(Set(watch.tasks.map(\.id)).count, watch.tasks.count)
    }

    func testDelayedSnapshotDoesNotRestoreDeletedTask() throws {
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport)
        transport.disconnect()

        let a = try XCTUnwrap(phone.addTask(text: "A"))
        _ = try XCTUnwrap(phone.addTask(text: "B"))
        let olderSnapshot = try XCTUnwrap(transport.published.last)
        _ = phone.deleteTask(id: a.id)
        let latestSnapshot = try XCTUnwrap(transport.published.last)

        // Latest arrives first, then the stale (older) snapshot.
        let watch1Defaults = try makeDefaults()
        let watch1Transport = ControllableTaskTransport()
        let watch1 = try makeWatch(defaults: watch1Defaults, transport: watch1Transport)
        watch1Transport.deliver(latestSnapshot)
        watch1Transport.deliver(olderSnapshot)
        XCTAssertFalse(watch1.tasks.contains { $0.id == a.id })

        let reopenedTransport = ControllableTaskTransport()
        let watch1Reopened = try makeWatch(defaults: watch1Defaults, transport: reopenedTransport)
        XCTAssertFalse(watch1Reopened.tasks.contains { $0.id == a.id })

        // The reopened Watch's persisted revision still blocks the stale snapshot.
        reopenedTransport.deliver(olderSnapshot)
        XCTAssertFalse(watch1Reopened.tasks.contains { $0.id == a.id })

        // Older arrives first, then the latest snapshot.
        let watch2Defaults = try makeDefaults()
        let watch2Transport = ControllableTaskTransport()
        let watch2 = try makeWatch(defaults: watch2Defaults, transport: watch2Transport)
        watch2Transport.deliver(olderSnapshot)
        watch2Transport.deliver(latestSnapshot)
        XCTAssertFalse(watch2.tasks.contains { $0.id == a.id })
    }

    func testRolloverCarriesUnfinishedTasksOnWatchWithoutNewDelivery() throws {
        let calendar = Calendar(identifier: .gregorian)
        var phoneNow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 23, minute: 59)))
        var watchNow = phoneNow
        let transport = ControllableTaskTransport()
        let phone = try makePhone(transport: transport, now: { phoneNow }, calendar: calendar)
        let watch = try makeWatch(transport: transport, now: { watchNow }, calendar: calendar)

        let first = try XCTUnwrap(phone.addTask(text: "First"))
        _ = try XCTUnwrap(phone.addTask(text: "Second"))
        let third = try XCTUnwrap(phone.addTask(text: "Third"))
        let second = try XCTUnwrap(phone.tasks.first { $0.text == "Second" })
        _ = phone.toggleTask(id: second.id)
        XCTAssertEqual(watch.tasks, phone.tasks)

        transport.disconnect()

        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 0, minute: 1)))
        phoneNow = nextDay
        watchNow = nextDay
        watch.refreshForCurrentDay()

        XCTAssertEqual(watch.currentDate, calendar.startOfDay(for: nextDay))
        XCTAssertEqual(watch.tasks.map(\.id), [first.id, third.id])
        XCTAssertEqual(watch.completedCount, 0)
        XCTAssertEqual(watch.incompleteCount, 2)

        phone.refreshForCurrentDay()
        XCTAssertEqual(phone.tasks, watch.tasks)

        transport.reconnect()
        _ = try XCTUnwrap(phone.addTask(text: "New today"))
        XCTAssertEqual(watch.tasks.map(\.text), ["First", "Third", "New today"])

        watch.refreshForCurrentDay()
        watch.refreshForCurrentDay()
        XCTAssertEqual(watch.taskCount, 3)
        XCTAssertEqual(Set(watch.tasks.map(\.id)).count, 3)
    }

    func testWatchAcceptsListFromReinstalledPhone() throws {
        let transport = ControllableTaskTransport()
        let calendar = Calendar(identifier: .gregorian)
        let p1Now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        let phone1 = try makePhone(transport: transport, now: { p1Now }, calendar: calendar)
        _ = try XCTUnwrap(phone1.addTask(text: "Old task"))

        let watch = try makeWatch(transport: transport, calendar: calendar)
        XCTAssertEqual(watch.tasks.map(\.text), ["Old task"])

        let p2Now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27)))
        let phone2Defaults = try makeDefaults()
        let phone2 = try makePhone(defaults: phone2Defaults, transport: transport, now: { p2Now }, calendar: calendar)
        _ = try XCTUnwrap(phone2.addTask(text: "Fresh"))

        XCTAssertEqual(watch.tasks, phone2.tasks)
        XCTAssertEqual(watch.tasks.map(\.text), ["Fresh"])
        XCTAssertFalse(watch.tasks.contains { $0.text == "Old task" })
    }

    func testWatchShowsReinstalledPhonesEmptyListEvenWithoutAnyChanges() throws {
        let transport = ControllableTaskTransport()
        let calendar = Calendar(identifier: .gregorian)
        let p1Now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        let phone1 = try makePhone(transport: transport, now: { p1Now }, calendar: calendar)
        _ = try XCTUnwrap(phone1.addTask(text: "Old task"))

        let watch = try makeWatch(transport: transport, calendar: calendar)
        XCTAssertEqual(watch.tasks.map(\.text), ["Old task"])

        // Phone 2 is reinstalled (new defaults, later clock) but makes no changes of its own.
        // Its store-creation publish must still seed a revision high enough to be accepted,
        // or the Watch would keep showing phone 1's list forever.
        let p2Now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27)))
        let phone2Defaults = try makeDefaults()
        let phone2 = try makePhone(defaults: phone2Defaults, transport: transport, now: { p2Now }, calendar: calendar)

        XCTAssertEqual(watch.tasks, phone2.tasks)
        XCTAssertTrue(watch.tasks.isEmpty)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "TaskListSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePhone(
        defaults: UserDefaults? = nil,
        transport: any TaskSnapshotTransport,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> TaskListStore {
        TaskListStore(
            userDefaults: try defaults ?? makeDefaults(),
            storageKey: "phone",
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
