import Foundation

/// How long the Watch keeps a `WKWatchConnectivityRefreshBackgroundTask` open. Apple's guidance
/// is to hold the task until the session is activated and `hasContentPending` is false, so
/// everything the phone sent (a memo snapshot with `acknowledgedMemoIDs`, task and habit
/// snapshots) has reached the delegate and been applied before the task completes. The system
/// ends a background task that runs too long, so the wait gives up after `timeout`.
enum WatchConnectivityRefresh {
    /// Waits until `isSettled` is `true`, checking every `poll`, for at most `timeout`. Returns
    /// whether it settled.
    @discardableResult
    static func wait(
        timeout: Duration = .seconds(20),
        poll: Duration = .milliseconds(250),
        until isSettled: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await isSettled()) {
            guard ContinuousClock.now < deadline else { return false }
            // Also lets the main-actor work the delegate callbacks started run.
            try? await Task.sleep(for: poll)
        }
        return true
    }
}
