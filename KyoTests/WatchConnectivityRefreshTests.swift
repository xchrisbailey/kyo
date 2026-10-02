import XCTest

/// The wait a Watch Connectivity background task does before it completes: until the session is
/// activated and has nothing pending (ADR 0005). The task itself needs a real `WKExtension`
/// wake, so it's checked on a paired Watch; the snapshot handling it calls is covered by
/// `WatchRecordingTests`.
@MainActor
final class WatchConnectivityRefreshTests: XCTestCase {
    private final class Session {
        var isActivated = false
        var hasContentPending = true
        var checks = 0

        var isSettled: Bool {
            checks += 1
            return isActivated && !hasContentPending
        }
    }

    func testItReturnsAtOnceWhenTheSessionIsAlreadySettled() async {
        let session = Session()
        session.isActivated = true
        session.hasContentPending = false

        let settled = await WatchConnectivityRefresh.wait(timeout: .seconds(5), poll: .milliseconds(5)) { session.isSettled }

        XCTAssertTrue(settled)
        XCTAssertEqual(session.checks, 1)
    }

    func testItKeepsWaitingWhileContentIsPendingThenReturnsOnceItIsDelivered() async {
        let session = Session()
        session.isActivated = true
        let finish = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            session.hasContentPending = false
        }

        let settled = await WatchConnectivityRefresh.wait(timeout: .seconds(5), poll: .milliseconds(5)) { session.isSettled }
        await finish.value

        XCTAssertTrue(settled)
        XCTAssertGreaterThan(session.checks, 1)
    }

    func testItWaitsForActivation() async {
        let session = Session()
        session.hasContentPending = false
        let activate = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            session.isActivated = true
        }

        let settled = await WatchConnectivityRefresh.wait(timeout: .seconds(5), poll: .milliseconds(5)) { session.isSettled }
        await activate.value

        XCTAssertTrue(settled)
    }

    func testItGivesUpAtTheTimeoutSoTheTaskIsNotHeldForever() async {
        let session = Session()

        let settled = await WatchConnectivityRefresh.wait(timeout: .milliseconds(50), poll: .milliseconds(5)) { session.isSettled }

        XCTAssertFalse(settled)
    }
}
