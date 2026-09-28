import Foundation

/// A full copy of the current day's task list, exchanged between the phone and the Watch.
///
/// See `docs/adr/0001-phone-authoritative-task-snapshots.md` for the reconciliation rule
/// that governs when a received snapshot replaces the receiver's stored tasks, and
/// `docs/adr/0002-watch-commands-and-phone-reconciliation.md` for `acknowledgedCommandIDs`,
/// which lets the Watch retire commands from its outbox once the phone has processed them.
struct TaskListSnapshot: Codable, Equatable, Sendable {
    let revision: Int64
    let tasks: [DailyTask]
    let acknowledgedCommandIDs: [UUID]

    init(revision: Int64, tasks: [DailyTask], acknowledgedCommandIDs: [UUID] = []) {
        self.revision = revision
        self.tasks = tasks
        self.acknowledgedCommandIDs = acknowledgedCommandIDs
    }

    private enum CodingKeys: String, CodingKey {
        case revision, tasks, acknowledgedCommandIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(Int64.self, forKey: .revision)
        tasks = try container.decode([DailyTask].self, forKey: .tasks)
        // Old payloads (before #14) never carried this field; treat it as an empty ack set
        // rather than failing to decode.
        acknowledgedCommandIDs = try container.decodeIfPresent([UUID].self, forKey: .acknowledgedCommandIDs) ?? []
    }
}

/// A Watch-originated mutation sent to the phone. See
/// `docs/adr/0002-watch-commands-and-phone-reconciliation.md`.
///
/// `id` identifies the command itself (for idempotency across retries and duplicate
/// delivery), separate from the task id the command acts on.
struct TaskCommand: Codable, Equatable, Sendable {
    enum Action: Codable, Equatable, Sendable {
        /// A new task. Carries no `creationOrder`: the phone assigns one on receipt, so
        /// Watch-originated adds always sort after the phone's own tasks at the moment they
        /// are applied.
        case add(taskID: UUID, text: String)
        /// The task's absolute completion state, computed from the Watch's own clock/calendar
        /// at the time of the toggle, so completion-day retention follows the Watch's day.
        case setCompletion(taskID: UUID, isComplete: Bool, completedOn: TaskCompletionDay?)
        /// The task's full new text, already trimmed and nonblank. Applied last-wins, like
        /// completion; ignored if the task no longer exists.
        case rename(taskID: UUID, text: String)
        /// Deletion is final: the phone tombstones the id even if the task is already gone.
        case delete(taskID: UUID)
    }

    let id: UUID
    let action: Action
}

/// Carries `TaskListSnapshot`s from the phone to the Watch, and `TaskCommand`s from the Watch
/// to the phone. The phone publishes snapshots and applies commands; the Watch mirrors
/// snapshots and sends commands. Concrete transports (see `WatchConnectivityTaskTransport`)
/// may drop undelivered snapshots in favor of the latest one, but must queue and eventually
/// deliver every command.
@MainActor
protocol TaskSnapshotTransport: AnyObject {
    /// Makes `snapshot` the latest list available to the counterpart. Latest wins; undelivered earlier snapshots may be dropped.
    func publish(_ snapshot: TaskListSnapshot)
    /// Registers the receiver. If a snapshot was already received, deliver the latest one immediately.
    func setSnapshotHandler(_ handler: @escaping @MainActor (TaskListSnapshot) -> Void)
    /// Queues `command` for delivery to the counterpart. Unlike `publish`, no command may be
    /// dropped: every command must eventually reach the handler, in the order sent.
    func send(_ command: TaskCommand)
    /// Registers the receiver. Any commands already queued before this call are delivered
    /// immediately, in order.
    func setCommandHandler(_ handler: @escaping @MainActor (TaskCommand) -> Void)
}

/// The role a `TaskListStore` plays in phone/Watch synchronization.
enum TaskListSync {
    case publish(to: any TaskSnapshotTransport)   // phone
    case mirror(from: any TaskSnapshotTransport)  // Watch
}
