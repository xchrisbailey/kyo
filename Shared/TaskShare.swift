import Foundation

/// What the iOS share sheet receives for a **Task**: its text exactly as saved, as one item, with
/// nothing added before or after it. Kyo wraps no prompt around it and keeps no record that it was
/// shared.
struct TaskSharePayload: Equatable, Sendable {
    /// The Task's saved text.
    let text: String

    /// The payload for `task`. This is always the saved `text`, never an inline edit in progress.
    static func make(for task: DailyTask) -> TaskSharePayload {
        TaskSharePayload(text: task.text)
    }

    /// The items to hand to the share sheet: the text alone.
    var activityItems: [Any] { [text] }
}
