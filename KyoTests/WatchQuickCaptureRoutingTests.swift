import XCTest

/// Behavior of quick capture on the Watch, through the shared router. The Watch's Record memo
/// control calls `perform(.recordMemo)` from its intent, and a complication's `widgetURL` arrives
/// as `Action(url:)`. The Watch has no written memo, so it only ever reports `.none`, `.recorder`
/// or `.otherSheet` (a task or calendar sheet).
@MainActor
final class WatchQuickCaptureRoutingTests: XCTestCase {
    private typealias Command = QuickCaptureRouter.Command

    private func route(over surface: QuickCaptureRouter.Surface) throws -> Command {
        let router = QuickCaptureRouter()
        router.report(surface: surface)
        router.perform(.recordMemo)
        return try XCTUnwrap(router.pending).command
    }

    /// What the Watch's `onOpenURL` does with a complication tap.
    private func openComplication(on router: QuickCaptureRouter) {
        guard let action = QuickCaptureRouter.Action(url: QuickCaptureRouter.Action.recordMemoURL) else { return }
        router.perform(action)
    }

    // MARK: Starting a recording

    func testRecordMemoOverTodayOpensTheRecorderAndStartsRecording() throws {
        let command = try route(over: .none)
        XCTAssertEqual(command, Command(target: .recorder, startsNew: true, closesOpenSheets: false))
    }

    func testRecordMemoOverATaskOrCalendarSheetClosesItAndOpensTheRecorder() throws {
        let command = try route(over: .otherSheet)
        XCTAssertEqual(command, Command(target: .recorder, startsNew: true, closesOpenSheets: true))
    }

    // MARK: A recording in progress

    func testRecordMemoDuringARecordingBringsItForwardAndStartsNothing() throws {
        let command = try route(over: .recorder)
        XCTAssertEqual(command, Command(target: .recorder, startsNew: false, closesOpenSheets: false))
    }

    func testPressingTheControlTwiceDuringARecordingStartsNothingNew() throws {
        let router = QuickCaptureRouter()
        router.report(surface: .none)
        router.perform(.recordMemo)
        let first = try XCTUnwrap(router.pending)
        XCTAssertTrue(first.command.startsNew)
        router.markApplied(first)

        // Today applied the request, so the recorder is showing.
        router.report(surface: .recorder)
        router.perform(.recordMemo)

        let second = try XCTUnwrap(router.pending)
        XCTAssertFalse(second.command.startsNew)
        XCTAssertEqual(second.command.target, .recorder)
    }

    // MARK: Cold launch

    func testARequestFromAColdLaunchWaitsForTodayToApplyIt() throws {
        let router = QuickCaptureRouter()
        // The control's intent ran before Today reported anything.
        router.perform(.recordMemo)

        let request = try XCTUnwrap(router.pending)
        XCTAssertEqual(request.command, Command(target: .recorder, startsNew: true, closesOpenSheets: false))
        router.markApplied(request)
        XCTAssertNil(router.pending)
    }

    // MARK: Complication taps

    func testTheComplicationURLIsRecordMemo() {
        XCTAssertEqual(QuickCaptureRouter.Action(url: QuickCaptureRouter.Action.recordMemoURL), .recordMemo)
    }

    func testOtherURLsAreNotQuickCapture() {
        XCTAssertNil(QuickCaptureRouter.Action(url: URL(string: "kyo://write-memo")!))
        XCTAssertNil(QuickCaptureRouter.Action(url: URL(string: "https://example.com/record-memo")!))
    }

    func testTappingTheComplicationStartsARecordingLikeTheControl() throws {
        let router = QuickCaptureRouter()
        router.report(surface: .none)
        openComplication(on: router)

        XCTAssertEqual(
            router.pending?.command,
            Command(target: .recorder, startsNew: true, closesOpenSheets: false)
        )
    }

    func testTappingTheComplicationDuringARecordingBringsItForward() throws {
        let router = QuickCaptureRouter()
        router.report(surface: .recorder)
        openComplication(on: router)

        XCTAssertEqual(
            router.pending?.command,
            Command(target: .recorder, startsNew: false, closesOpenSheets: false)
        )
    }
}
