import XCTest

/// Behavior of quick capture's router: what **Record memo** and **Write memo** do against what
/// Today is showing. The router publishes one request for Today to apply; these tests read it.
@MainActor
final class QuickCaptureRoutingTests: XCTestCase {
    private typealias Command = QuickCaptureRouter.Command

    /// Reports `surface`, runs `action`, and returns what Today is asked to do.
    private func route(
        _ action: QuickCaptureRouter.Action,
        over surface: QuickCaptureRouter.Surface,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Command {
        let router = QuickCaptureRouter()
        router.report(surface: surface)
        router.perform(action)
        return try XCTUnwrap(router.pending, file: file, line: line).command
    }

    // MARK: Each action

    func testRecordMemoOpensTheRecorderOverToday() throws {
        let command = try route(.recordMemo, over: .none)
        XCTAssertEqual(command, Command(target: .recorder, startsNew: true, closesOpenSheets: false))
    }

    func testWriteMemoOpensTheComposeSheetOverToday() throws {
        let command = try route(.writeMemo, over: .none)
        XCTAssertEqual(command, Command(target: .compose, startsNew: true, closesOpenSheets: false))
    }

    // MARK: A recording or unsaved draft in progress

    func testRecordMemoDuringARecordingBringsItForwardAndStartsNothing() throws {
        let command = try route(.recordMemo, over: .recorder)
        XCTAssertEqual(command, Command(target: .recorder, startsNew: false, closesOpenSheets: false))
    }

    func testWriteMemoDuringARecordingBringsTheRecordingForward() throws {
        let command = try route(.writeMemo, over: .recorder)
        XCTAssertEqual(command, Command(target: .recorder, startsNew: false, closesOpenSheets: false))
    }

    func testWriteMemoWithAnUnsavedDraftBringsTheDraftForward() throws {
        let command = try route(.writeMemo, over: .compose(hasUnsavedDraft: true))
        XCTAssertEqual(command, Command(target: .compose, startsNew: false, closesOpenSheets: false))
    }

    func testRecordMemoWithAnUnsavedDraftBringsTheDraftForwardAndStartsNoRecording() throws {
        let command = try route(.recordMemo, over: .compose(hasUnsavedDraft: true))
        XCTAssertEqual(command, Command(target: .compose, startsNew: false, closesOpenSheets: false))
    }

    func testWriteMemoOverAnEmptyComposeSheetKeepsIt() throws {
        let command = try route(.writeMemo, over: .compose(hasUnsavedDraft: false))
        XCTAssertEqual(command, Command(target: .compose, startsNew: false, closesOpenSheets: false))
    }

    func testRecordMemoOverAnEmptyComposeSheetReplacesItWithTheRecorder() throws {
        let command = try route(.recordMemo, over: .compose(hasUnsavedDraft: false))
        XCTAssertEqual(command, Command(target: .recorder, startsNew: true, closesOpenSheets: true))
    }

    // MARK: Other UI closes

    func testRecordMemoOverAnOpenSheetClosesItAndOpensTheRecorder() throws {
        let command = try route(.recordMemo, over: .otherSheet)
        XCTAssertEqual(command, Command(target: .recorder, startsNew: true, closesOpenSheets: true))
    }

    func testWriteMemoOverAnOpenSheetClosesItAndOpensTheComposeSheet() throws {
        let command = try route(.writeMemo, over: .otherSheet)
        XCTAssertEqual(command, Command(target: .compose, startsNew: true, closesOpenSheets: true))
    }

    // MARK: Delivery to Today

    func testARequestWaitsUntilTodayAppliesIt() throws {
        let router = QuickCaptureRouter()
        // A cold launch: the intent runs before Today has reported anything.
        router.perform(.recordMemo)
        let request = try XCTUnwrap(router.pending)
        XCTAssertEqual(request.command.target, .recorder)

        router.markApplied(request)

        XCTAssertNil(router.pending)
    }

    func testANewerRequestSurvivesTheOlderOneBeingApplied() throws {
        let router = QuickCaptureRouter()
        router.perform(.recordMemo)
        let first = try XCTUnwrap(router.pending)
        router.perform(.writeMemo)

        router.markApplied(first)

        XCTAssertEqual(router.pending?.command.target, .compose)
    }

    func testTheSameActionTwiceIsTwoRequests() throws {
        let router = QuickCaptureRouter()
        router.perform(.recordMemo)
        let first = try XCTUnwrap(router.pending)
        router.markApplied(first)
        router.perform(.recordMemo)

        XCTAssertNotEqual(router.pending, first)
    }

    func testTheRouterRoutesAgainstWhatTodayLastReported() throws {
        let router = QuickCaptureRouter()
        router.report(surface: .recorder)
        router.report(surface: .none)
        router.perform(.recordMemo)

        XCTAssertEqual(router.pending?.command, Command(target: .recorder, startsNew: true, closesOpenSheets: false))
    }
}
