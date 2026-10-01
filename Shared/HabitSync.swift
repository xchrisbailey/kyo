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

    init(revision: Int64, habits: [Habit]) {
        self.revision = revision
        self.habits = habits
    }

    /// A snapshot of `habits` with every log trimmed as of `date`.
    init(revision: Int64, habits: [Habit], trimmedOn date: Date, calendar: Calendar) {
        self.init(revision: revision, habits: habits.map { $0.trimmedLog(on: date, calendar: calendar) })
    }
}

/// Carries `HabitListSnapshot`s from the phone to the Watch. Like task snapshots, undelivered
/// earlier snapshots may be dropped in favor of the latest. (No commands yet: check-off from
/// the Watch is a later slice.)
@MainActor
protocol HabitSnapshotTransport: AnyObject {
    /// Makes `snapshot` the latest habit list available to the counterpart.
    func publish(_ snapshot: HabitListSnapshot)
    /// Registers the receiver. If a snapshot was already received, deliver the latest one immediately.
    func setHabitSnapshotHandler(_ handler: @escaping @MainActor (HabitListSnapshot) -> Void)
}

/// The role a `HabitListStore` plays in phone/Watch synchronization.
enum HabitListSync {
    case publish(to: any HabitSnapshotTransport)   // phone
    case mirror(from: any HabitSnapshotTransport)  // Watch
}
