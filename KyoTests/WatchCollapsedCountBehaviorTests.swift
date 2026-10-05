import XCTest

/// The count a collapsed section header shows at its right on Apple Watch: done over total for
/// Tasks and Habits, the number of memos for Memos, and nothing when there's nothing to count.
final class WatchCollapsedCountBehaviorTests: XCTestCase {
    func testProgressShowsDoneOverTotal() {
        let count = WatchCollapsedCount.progress(done: 2, total: 5)

        XCTAssertEqual(count?.text, "2/5")
    }

    func testProgressReadsAsDoneOfTotalForVoiceOver() {
        let count = WatchCollapsedCount.progress(done: 2, total: 5)

        XCTAssertEqual(count?.spoken, "2 of 5 done")
    }

    func testProgressShowsZeroDoneWhenNothingIsDone() {
        XCTAssertEqual(WatchCollapsedCount.progress(done: 0, total: 3)?.text, "0/3")
    }

    func testProgressShowsAllDoneWhenEverythingIsDone() {
        XCTAssertEqual(WatchCollapsedCount.progress(done: 4, total: 4)?.text, "4/4")
    }

    func testProgressShowsNothingWhenThereIsNothingToCount() {
        XCTAssertNil(WatchCollapsedCount.progress(done: 0, total: 0))
    }

    func testMemosShowTheNumberOfMemos() {
        let count = WatchCollapsedCount.memos(3)

        XCTAssertEqual(count?.text, "3")
        XCTAssertEqual(count?.spoken, "3 memos")
    }

    func testOneMemoReadsInTheSingular() {
        XCTAssertEqual(WatchCollapsedCount.memos(1)?.spoken, "1 memo")
    }

    func testMemosShowNothingWhenThereAreNone() {
        XCTAssertNil(WatchCollapsedCount.memos(0))
    }
}
