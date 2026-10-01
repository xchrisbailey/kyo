import Foundation

/// The phone's habits, exchanged with the Watch under their own revision so publishing habits
/// never disturbs the task snapshot. See `docs/adr/0003-habit-sync.md`.
///
/// Every habit is present (id, name, order, dated schedule history, creation day), but each
/// log is trimmed with `Habit.trimmedLog(on:calendar:)` to what the current streak and this
/// week's progress need. The revision follows ADR 0001's hybrid clock and reconciliation rule.
struct HabitListSnapshot: Codable, Equatable, Sendable {
    let revision: Int64
    let habits: [Habit]
    /// Ids of the Watch commands the phone has processed (applied or deliberately ignored), so
    /// the Watch can retire them from its outbox. See ADR 0002.
    let acknowledgedCommandIDs: [UUID]

    init(revision: Int64, habits: [Habit], acknowledgedCommandIDs: [UUID] = []) {
        self.revision = revision
        self.habits = habits
        self.acknowledgedCommandIDs = acknowledgedCommandIDs
    }

    /// A snapshot of `habits` with every log trimmed as of `date`.
    init(revision: Int64, habits: [Habit], acknowledgedCommandIDs: [UUID] = [], trimmedOn date: Date, calendar: Calendar) {
        self.init(
            revision: revision,
            habits: habits.map { $0.trimmedLog(on: date, calendar: calendar) },
            acknowledgedCommandIDs: acknowledgedCommandIDs
        )
    }

    private enum CodingKeys: String, CodingKey {
        case revision, habits, acknowledgedCommandIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(Int64.self, forKey: .revision)
        habits = try container.decode([Habit].self, forKey: .habits)
        // Snapshots published before Watch check-off never carried this field.
        acknowledgedCommandIDs = try container.decodeIfPresent([UUID].self, forKey: .acknowledgedCommandIDs) ?? []
    }
}

/// A Watch-originated habit mutation sent to the phone. See `docs/adr/0003-habit-sync.md`.
///
/// `id` identifies the command itself (idempotency under retry and duplicate delivery),
/// separate from the habit it acts on.
struct HabitCommand: Codable, Equatable, Sendable {
    enum Action: Codable, Equatable, Sendable {
        /// The habit's absolute check-off state for `day`: the Watch's local calendar date when
        /// the user tapped. The phone records it even if it arrives late, and ignores it (still
        /// acknowledging it) if the habit no longer exists.
        case setCheckOff(habitID: UUID, day: TaskCompletionDay, isCheckedOff: Bool)
    }

    let id: UUID
    let action: Action
}

/// Carries `HabitListSnapshot`s from the phone to the Watch, and `HabitCommand`s from the Watch
/// to the phone. Like task snapshots, undelivered earlier snapshots may be dropped in favor of
/// the latest; commands must all be delivered, in order.
@MainActor
protocol HabitSnapshotTransport: AnyObject {
    /// Makes `snapshot` the latest habit list available to the counterpart.
    func publish(_ snapshot: HabitListSnapshot)
    /// Registers the receiver. If a snapshot was already received, deliver the latest one immediately.
    func setHabitSnapshotHandler(_ handler: @escaping @MainActor (HabitListSnapshot) -> Void)
    /// Queues `command` for delivery to the counterpart. No command may be dropped: every one
    /// must eventually reach the handler, in the order sent.
    func send(_ command: HabitCommand)
    /// Registers the receiver. Any commands already queued before this call are delivered
    /// immediately, in order.
    func setHabitCommandHandler(_ handler: @escaping @MainActor (HabitCommand) -> Void)
}

/// The role a `HabitListStore` plays in phone/Watch synchronization.
enum HabitListSync {
    case publish(to: any HabitSnapshotTransport)   // phone
    case mirror(from: any HabitSnapshotTransport)  // Watch
}
