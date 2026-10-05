import Foundation

/// The short count at the right of a collapsed **section** header on Apple Watch. Nothing is
/// returned when there's nothing to count, so the header shows no count.
struct WatchCollapsedCount: Equatable, Sendable {
    /// What the header shows, such as "2/5".
    let text: String
    /// What VoiceOver reads, such as "2 of 5 done".
    let spoken: String

    /// Done over total, for Tasks and for the habits on Today's list.
    static func progress(done: Int, total: Int) -> WatchCollapsedCount? {
        guard total > 0 else { return nil }
        return WatchCollapsedCount(text: "\(done)/\(total)", spoken: "\(done) of \(total) done")
    }

    /// The number of Today's memos.
    static func memos(_ count: Int) -> WatchCollapsedCount? {
        guard count > 0 else { return nil }
        return WatchCollapsedCount(text: "\(count)", spoken: count == 1 ? "1 memo" : "\(count) memos")
    }
}
