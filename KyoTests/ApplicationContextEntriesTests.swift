import XCTest

final class ApplicationContextEntriesTests: XCTestCase {
    private let keyA = "kyo.taskSnapshot"
    private let keyB = "kyo.habitSnapshot"

    private func payloads(_ entries: ApplicationContextEntries) -> [String: Data] {
        entries.context.compactMapValues { $0 as? Data }
    }

    func testStartsEmpty() {
        XCTAssertTrue(ApplicationContextEntries().isEmpty)
        XCTAssertTrue(ApplicationContextEntries().context.isEmpty)
    }

    func testPublishingKeyBKeepsKeyALatestPayload() {
        var entries = ApplicationContextEntries()
        entries.set(Data("a1".utf8), forKey: keyA)
        entries.set(Data("b1".utf8), forKey: keyB)

        XCTAssertEqual(payloads(entries), [keyA: Data("a1".utf8), keyB: Data("b1".utf8)])
    }

    func testPublishingKeyAKeepsKeyBLatestPayload() {
        var entries = ApplicationContextEntries()
        entries.set(Data("b1".utf8), forKey: keyB)
        entries.set(Data("a1".utf8), forKey: keyA)

        XCTAssertEqual(payloads(entries), [keyA: Data("a1".utf8), keyB: Data("b1".utf8)])
    }

    func testNewerPayloadReplacesOnlyItsOwnKey() {
        var entries = ApplicationContextEntries()
        entries.set(Data("a1".utf8), forKey: keyA)
        entries.set(Data("b1".utf8), forKey: keyB)
        entries.set(Data("a2".utf8), forKey: keyA)

        XCTAssertEqual(payloads(entries), [keyA: Data("a2".utf8), keyB: Data("b1".utf8)])
        XCTAssertEqual(entries.context.count, 2)
    }
}
