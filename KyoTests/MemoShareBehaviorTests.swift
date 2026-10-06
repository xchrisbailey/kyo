import SwiftData
import XCTest

/// What the share sheet receives for a **Memo**, through `MemoSharePayload`: the text (title, then
/// body or Transcript) plus the photos, never audio, with the time-stamped fallback title, and the
/// cases that share only photos or nothing. The share sheet itself is checked on device.
@MainActor
final class MemoShareBehaviorTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0) ?? .gmt
    private let english = Locale(identifier: "en_US")

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private func moment(hour: Int = 9, minute: Int = 41) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: hour, minute: minute)))
    }

    private func written(_ text: String, photoIDs: [UUID] = []) throws -> Memo {
        Memo(
            id: UUID(), kind: .written, createdAt: try moment(),
            day: TaskCompletionDay(era: 1, year: 2026, month: 9, day: 29),
            text: text, photoIDs: photoIDs
        )
    }

    private func voice(
        _ transcript: String = "",
        state: Memo.TranscriptState = .transcribed,
        title: String = "",
        photoIDs: [UUID] = [],
        hour: Int = 9
    ) throws -> Memo {
        Memo(
            id: UUID(), kind: .voice, createdAt: try moment(hour: hour),
            day: TaskCompletionDay(era: 1, year: 2026, month: 9, day: 29),
            text: transcript, duration: 42, transcriptState: state,
            voiceTitle: title, isTitleUserSet: !title.isEmpty, photoIDs: photoIDs
        )
    }

    private func payload(
        _ memo: Memo,
        currentText: String? = nil,
        photos: [Data] = [],
        locale: Locale? = nil,
        timeZone: TimeZone? = nil
    ) -> MemoSharePayload {
        MemoSharePayload.make(
            for: memo, currentText: currentText ?? memo.text, photos: photos,
            locale: locale ?? english, timeZone: timeZone ?? utc
        )
    }

    /// The system may separate the time from "AM" with a narrow no-break space.
    private func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private let photoA = Data([0x01, 0x02])
    private let photoB = Data([0x03, 0x04])

    // MARK: Written memos

    func testWrittenMemoSharesItsFirstLineThenItsBody() throws {
        let memo = try written("Trip ideas\nBook flights\nPack the camera")

        let shared = payload(memo)

        XCTAssertEqual(shared.text, "Trip ideas\n\nBook flights\nPack the camera")
        XCTAssertEqual(shared.photos, [])
    }

    func testWrittenMemoWithOnlyATitleSharesJustTheTitle() throws {
        XCTAssertEqual(payload(try written("Call the dentist")).text, "Call the dentist")
    }

    func testWrittenMemoSkipsLeadingBlankLinesAndTrimsTheEnds() throws {
        let shared = payload(try written("\n  \n  Groceries  \n\n milk \n\n"))

        XCTAssertEqual(shared.text, "Groceries\n\nmilk")
    }

    func testWrittenMemoSharesTheTextAsEditedInTheOpenCard() throws {
        let memo = try written("Old title\nold body")

        let shared = payload(memo, currentText: "New title\nnew body")

        XCTAssertEqual(shared.text, "New title\n\nnew body")
    }

    func testWrittenMemoSharesTextThenPhotosInOrder() throws {
        let memo = try written("Garden\nTomatoes", photoIDs: [UUID(), UUID()])

        let shared = payload(memo, photos: [photoA, photoB])

        XCTAssertEqual(shared.text, "Garden\n\nTomatoes")
        XCTAssertEqual(shared.photos, [photoA, photoB])
    }

    func testPhotoOnlyMemoSharesOnlyItsPhotosWithNoText() throws {
        let memo = try written("", photoIDs: [UUID()])

        let shared = payload(memo, photos: [photoA])

        XCTAssertNil(shared.text)
        XCTAssertEqual(shared.photos, [photoA])
        XCTAssertTrue(MemoSharePayload.canShare(memo, currentText: ""))
    }

    func testBlankWrittenMemoWithNoPhotosHasNothingToShare() throws {
        let memo = try written("  \n ")

        XCTAssertTrue(payload(memo).isEmpty)
        XCTAssertFalse(MemoSharePayload.canShare(memo, currentText: memo.text))
    }

    // MARK: Voice memos

    func testTranscribedVoiceMemoSharesItsTitleThenItsTranscript() throws {
        let memo = try voice("Pick up the parcel and call Sam.", title: "Errands")

        let shared = payload(memo)

        XCTAssertEqual(shared.text, "Errands\n\nPick up the parcel and call Sam.")
    }

    func testVoiceMemoWithoutATitleSharesTheTimeStampedFallbackTitle() throws {
        let shared = payload(try voice("Remember the milk."))

        XCTAssertEqual(plain(shared.text), "Voice memo · 9:41 AM\n\nRemember the milk.")
    }

    func testTimeStampedFallbackFollowsTheLocale() throws {
        let shared = payload(try voice("Cheers.", hour: 15), locale: Locale(identifier: "en_GB"))

        XCTAssertEqual(plain(shared.text), "Voice memo · 15:41\n\nCheers.")
    }

    func testTimeStampedFallbackFollowsTheTimeZone() throws {
        let plusTwo = try XCTUnwrap(TimeZone(secondsFromGMT: 2 * 3600))

        let shared = payload(try voice("Later."), timeZone: plusTwo)

        XCTAssertEqual(plain(shared.text), "Voice memo · 11:41 AM\n\nLater.")
    }

    func testAUserTitleIsSharedAsItIsWithNoTimeStamp() throws {
        let shared = payload(try voice("Notes.", title: "Standup"))

        XCTAssertEqual(shared.text, "Standup\n\nNotes.")
    }

    func testVoiceMemoSharesTheTranscriptAsEditedInTheOpenCard() throws {
        let memo = try voice("Teh plan", title: "Plan")

        XCTAssertEqual(payload(memo, currentText: "The plan").text, "Plan\n\nThe plan")
    }

    func testVoiceMemoSharesItsTranscriptThenItsPhotos() throws {
        let memo = try voice("Look at this.", title: "Sketch", photoIDs: [UUID()])

        let shared = payload(memo, photos: [photoA])

        XCTAssertEqual(shared.text, "Sketch\n\nLook at this.")
        XCTAssertEqual(shared.photos, [photoA])
    }

    func testTranscribingVoiceMemoSharesOnlyItsPhotos() throws {
        let memo = try voice(state: .transcribing, title: "Draft", photoIDs: [UUID()])

        let shared = payload(memo, photos: [photoA])

        XCTAssertNil(shared.text)
        XCTAssertEqual(shared.photos, [photoA])
        XCTAssertTrue(MemoSharePayload.canShare(memo, currentText: ""))
    }

    func testVoiceMemoWithNoTranscriptSharesOnlyItsPhotos() throws {
        let memo = try voice(state: .noTranscript, photoIDs: [UUID(), UUID()])

        let shared = payload(memo, photos: [photoA, photoB])

        XCTAssertNil(shared.text)
        XCTAssertEqual(shared.photos, [photoA, photoB])
    }

    func testTranscribingVoiceMemoWithoutPhotosHasNothingToShare() throws {
        let memo = try voice(state: .transcribing)

        XCTAssertTrue(payload(memo).isEmpty)
        XCTAssertFalse(MemoSharePayload.canShare(memo, currentText: ""))
    }

    func testVoiceMemoWithNoTranscriptAndNoPhotosHasNothingToShare() throws {
        let memo = try voice(state: .noTranscript, title: "Standup")

        XCTAssertTrue(payload(memo).isEmpty)
        XCTAssertFalse(MemoSharePayload.canShare(memo, currentText: ""))
    }

    func testTranscribedVoiceMemoWhoseTranscriptWasEmptiedSharesOnlyItsPhotos() throws {
        let memo = try voice("Hello", title: "Greeting", photoIDs: [UUID()])

        let shared = payload(memo, currentText: "  ", photos: [photoA])

        XCTAssertNil(shared.text)
        XCTAssertEqual(shared.photos, [photoA])
        XCTAssertFalse(MemoSharePayload.canShare(try voice("Hello", title: "Greeting"), currentText: ""))
    }

    // MARK: Availability and photo loading

    func testShareIsAvailableForAMemoWithText() throws {
        let memo = try written("Plan the week")

        XCTAssertTrue(MemoSharePayload.canShare(memo, currentText: memo.text))
        XCTAssertTrue(MemoSharePayload.canShare(try voice("Spoken."), currentText: "Spoken."))
    }

    // MARK: Sharing from a row

    func testRowOffersShareForAWrittenMemoWithText() throws {
        XCTAssertTrue(MemoSharePayload.canShare(try written("Plan the week")))
    }

    func testRowOffersShareForATranscribedVoiceMemo() throws {
        XCTAssertTrue(MemoSharePayload.canShare(try voice("Spoken.")))
    }

    func testRowOffersNoShareForATranscribingOrNoTranscriptVoiceMemoWithoutPhotos() throws {
        XCTAssertFalse(MemoSharePayload.canShare(try voice(state: .transcribing)))
        XCTAssertFalse(MemoSharePayload.canShare(try voice(state: .noTranscript)))
    }

    func testRowOffersShareForAVoiceMemoWithoutATranscriptWhenItHasPhotos() throws {
        let photoIDs = [UUID()]

        XCTAssertTrue(MemoSharePayload.canShare(try voice(state: .transcribing, photoIDs: photoIDs)))
        XCTAssertTrue(MemoSharePayload.canShare(try voice(state: .noTranscript, photoIDs: photoIDs)))
    }

    func testRowOffersShareForAPhotoOnlyMemoButNotABlankOne() throws {
        XCTAssertTrue(MemoSharePayload.canShare(try written("", photoIDs: [UUID()])))
        XCTAssertFalse(MemoSharePayload.canShare(try written("  \n ")))
    }

    func testARowSharesTheSameThingTheOpenCardWouldForTheMemoAsSaved() throws {
        let ids = [UUID(), UUID()]
        let bytes = [ids[0]: photoA, ids[1]: photoB]
        let memos = [
            try written("Garden\nTomatoes", photoIDs: ids),
            try voice("Look at this.", title: "Sketch", photoIDs: ids),
            try written("", photoIDs: ids),
            try voice(state: .noTranscript, photoIDs: ids),
        ]

        for memo in memos {
            let fromRow = MemoSharePayload.make(
                for: memo, currentText: memo.text, loadPhoto: { bytes[$0] }, locale: english, timeZone: utc
            )
            let fromCard = payload(memo, currentText: memo.text, photos: [photoA, photoB])
            XCTAssertEqual(fromRow, fromCard)
        }
    }

    func testPhotoBytesAreReadOnlyWhenThePayloadIsBuiltInPhotoOrder() throws {
        let ids = [UUID(), UUID(), UUID()]
        let memo = try written("Trip", photoIDs: ids)
        var reads: [UUID] = []

        XCTAssertTrue(MemoSharePayload.canShare(memo))
        XCTAssertTrue(reads.isEmpty)

        let shared = MemoSharePayload.make(for: memo, currentText: memo.text, loadPhoto: { id in
            reads.append(id)
            // The middle photo can't be read, so it is left out.
            return id == ids[1] ? nil : Data([UInt8(reads.count)])
        })

        XCTAssertEqual(reads, ids)
        XCTAssertEqual(shared.photos, [Data([1]), Data([3])])
    }

    func testPayloadFromAStoredMemoCarriesThePhotoBytesTheStoreHolds() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let clock = try moment()
        let store = MemoStore(modelContainer: container, now: { clock }, calendar: calendar)
        let first = StoredPhoto(data: photoA, thumbnail: Data([0x09]))
        let second = StoredPhoto(data: photoB, thumbnail: Data([0x0A]))
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Holiday\nBeach day", photos: [first, second]))

        let shared = payload(memo, photos: memo.photoIDs.compactMap { store.photoData(forPhotoID: $0) })

        XCTAssertEqual(shared.text, "Holiday\n\nBeach day")
        XCTAssertEqual(shared.photos, [photoA, photoB])
    }
}
