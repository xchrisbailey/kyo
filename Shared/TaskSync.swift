import Foundation

/// A full copy of the current day's task list, exchanged between the phone and the Watch.
///
/// See `docs/adr/0001-phone-authoritative-task-snapshots.md` for the reconciliation rule
/// that governs when a received snapshot replaces the receiver's stored tasks.
struct TaskListSnapshot: Codable, Equatable, Sendable {
    let revision: Int64
    let tasks: [DailyTask]
}

/// Carries `TaskListSnapshot`s between the phone and the Watch. The phone publishes; the
/// Watch mirrors. Concrete transports (see `WatchConnectivityTaskTransport`) may drop
/// undelivered snapshots in favor of the latest one.
@MainActor
protocol TaskSnapshotTransport: AnyObject {
    /// Makes `snapshot` the latest list available to the counterpart. Latest wins; undelivered earlier snapshots may be dropped.
    func publish(_ snapshot: TaskListSnapshot)
    /// Registers the receiver. If a snapshot was already received, deliver the latest one immediately.
    func setSnapshotHandler(_ handler: @escaping @MainActor (TaskListSnapshot) -> Void)
}

/// The role a `TaskListStore` plays in phone/Watch synchronization.
enum TaskListSync {
    case publish(to: any TaskSnapshotTransport)   // phone
    case mirror(from: any TaskSnapshotTransport)  // Watch
}
