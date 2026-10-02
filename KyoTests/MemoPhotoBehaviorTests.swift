import CoreGraphics
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest

/// Behavior of **Memo** photos through `MemoStoreBehavior` and `VoiceRecordingSession`, on an
/// in-memory store, with small generated images. The camera and the system photo picker are
/// checked on device.
@MainActor
final class MemoPhotoBehaviorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private func moment(_ day: Int, _ hour: Int = 9, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    private func makeStore(_ container: ModelContainer) throws -> MemoStore {
        let clock = try moment(29)
        return MemoStore(modelContainer: container, now: { clock }, calendar: calendar)
    }

    // MARK: Generated images

    /// A flat image of the given size, encoded as PNG (or JPEG with an EXIF orientation).
    private func imageData(
        width: Int,
        height: Int,
        type: UTType = .png,
        orientation: Int? = nil
    ) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func photo(width: Int = 64, height: Int = 48) throws -> StoredPhoto {
        try XCTUnwrap(MemoPhotoEncoder.encode(imageData(width: width, height: height)))
    }

    private func photos(_ count: Int) throws -> [StoredPhoto] {
        try (0..<count).map { _ in try photo() }
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
            try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    private func format(of data: Data) throws -> String? {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceGetType(source) as String?
    }

    private func photoRecordCount(_ container: ModelContainer) throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<MemoPhotoRecord>())
    }

    // MARK: Encoding

    func testALargePhotoIsStoredAsHEICWithItsLongestEdgeAt2048() throws {
        let stored = try XCTUnwrap(MemoPhotoEncoder.encode(imageData(width: 4000, height: 3000)))

        XCTAssertEqual(try format(of: stored.data), UTType.heic.identifier)
        let size = try pixelSize(of: stored.data)
        XCTAssertEqual(size.width, 2048)
        XCTAssertEqual(size.height, 1536)
    }

    func testATallPhotoIsLimitedByItsHeight() throws {
        let stored = try XCTUnwrap(MemoPhotoEncoder.encode(imageData(width: 1500, height: 3000)))

        let size = try pixelSize(of: stored.data)
        XCTAssertEqual(size.height, 2048)
        XCTAssertEqual(size.width, 1024)
    }

    func testASmallPhotoIsNeverScaledUp() throws {
        let stored = try XCTUnwrap(MemoPhotoEncoder.encode(imageData(width: 640, height: 480)))

        XCTAssertEqual(try format(of: stored.data), UTType.heic.identifier)
        let size = try pixelSize(of: stored.data)
        XCTAssertEqual(size.width, 640)
        XCTAssertEqual(size.height, 480)
    }

    func testAPhotoTakenSidewaysIsStoredUpright() throws {
        // Landscape pixels flagged as rotated a quarter turn: upright, it's portrait.
        let source = try imageData(width: 400, height: 200, type: .jpeg, orientation: 6)

        let stored = try XCTUnwrap(MemoPhotoEncoder.encode(source))

        let size = try pixelSize(of: stored.data)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 400)
    }

    func testEveryPhotoHasASmallThumbnail() throws {
        let stored = try XCTUnwrap(MemoPhotoEncoder.encode(imageData(width: 4000, height: 3000)))

        let size = try pixelSize(of: stored.thumbnail)
        XCTAssertEqual(max(size.width, size.height), MemoPhotoEncoder.thumbnailEdge)
        XCTAssertLessThan(stored.thumbnail.count, stored.data.count)
    }

    func testSomethingThatIsNotAnImageIsNotAPhoto() {
        XCTAssertNil(MemoPhotoEncoder.encode(Data([1, 2, 3, 4])))
    }

    // MARK: Adding

    func testAWrittenMemoCanBeSavedWithTextAndPhotosInOrder() throws {
        let store: any MemoStoreBehavior = try makeStore(try KyoModelContainer.make(inMemory: true))
        let first = try photo(width: 64, height: 48)
        let second = try photo(width: 32, height: 24)

        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Trail map\nTook this at the fork", photos: [first, second]))

        XCTAssertEqual(memo.title, "Trail map")
        XCTAssertEqual(memo.photoIDs, [first.id, second.id])
        XCTAssertEqual(memo.photoCount, 2)
        XCTAssertFalse(memo.isPhotoOnly)
        XCTAssertEqual(store.memos, [memo])
        XCTAssertEqual(store.photoData(forPhotoID: first.id), first.data)
        XCTAssertEqual(store.photoData(forPhotoID: second.id), second.data)
    }

    func testAMemoOfOnlyPhotosIsSavedAndTitledPhotoMemo() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))

        let memo = try XCTUnwrap(store.addWrittenMemo(text: "  \n", photos: try photos(1)))

        XCTAssertEqual(memo.title, "Photo memo")
        XCTAssertNil(memo.detail)
        XCTAssertEqual(memo.text, "")
        XCTAssertTrue(memo.isPhotoOnly)
        XCTAssertEqual(store.memos.map(\.title), ["Photo memo"])
        XCTAssertEqual(store.sectionSubtitle, "1 memo")
    }

    func testAMemoWithNoTextAndNoPhotosIsDiscarded() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let store = try makeStore(container)

        XCTAssertNil(store.addWrittenMemo(text: "", photos: []))

        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 0)
    }

    func testAMemoSavedWithMoreThanFourPhotosKeepsTheFirstFour() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let many = try photos(6)

        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Lots", photos: many))

        XCTAssertEqual(memo.photoIDs, many.prefix(4).map(\.id))
    }

    func testAPhotoCanBeAddedToAnOpenMemoAfterTheOnesItHas() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let first = try photo()
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Note", photos: [first]))
        let added = try photo()

        let updated = try XCTUnwrap(store.addPhoto(added, toMemoID: memo.id))

        XCTAssertEqual(updated.photoIDs, [first.id, added.id])
        XCTAssertEqual(store.memo(id: memo.id), updated)
        XCTAssertEqual(store.memos, [updated])
    }

    func testAFifthPhotoIsRefusedAndTheMemoIsUnchanged() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Full", photos: try photos(4)))
        let extra = try photo()

        XCTAssertNil(store.addPhoto(extra, toMemoID: memo.id))

        XCTAssertEqual(store.memo(id: memo.id)?.photoCount, 4)
        XCTAssertNil(store.photoData(forPhotoID: extra.id))
    }

    func testRemovingAPhotoMakesRoomForAnother() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let four = try photos(4)
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Full", photos: four))

        _ = store.removePhoto(id: four[1].id, fromMemoID: memo.id)
        let added = try photo()
        let updated = try XCTUnwrap(store.addPhoto(added, toMemoID: memo.id))

        XCTAssertEqual(updated.photoIDs, [four[0].id, four[2].id, four[3].id, added.id])
    }

    func testAddingThePhotoAMemoAlreadyHasChangesNothing() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let one = try photo()
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Once", photos: [one]))

        let again = try XCTUnwrap(store.addPhoto(one, toMemoID: memo.id))

        XCTAssertEqual(again.photoIDs, [one.id])
    }

    func testAddingAPhotoToAnUnknownMemoDoesNothing() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let store = try makeStore(container)

        XCTAssertNil(store.addPhoto(try photo(), toMemoID: UUID()))
        XCTAssertEqual(try photoRecordCount(container), 0)
    }

    func testAThumbnailComesFromItsPhotoAndAnUnknownIDHasNone() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let one = try photo()
        _ = store.addWrittenMemo(text: "", photos: [one])

        XCTAssertEqual(store.thumbnailData(forPhotoID: one.id), one.thumbnail)
        XCTAssertNil(store.thumbnailData(forPhotoID: UUID()))
        XCTAssertNil(store.photoData(forPhotoID: UUID()))
    }

    func testPhotosPersistAcrossReopeningInTheirOrder() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let store = try makeStore(container)
        let two = try photos(2)
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Kept", photos: two))

        let reopened = try makeStore(container)

        XCTAssertEqual(reopened.memos, [memo])
        XCTAssertEqual(reopened.memos.first?.photoIDs, two.map(\.id))
        XCTAssertEqual(reopened.photoData(forPhotoID: two[0].id), two[0].data)
    }

    // MARK: Removing

    func testRemovingAPhotoDeletesIt() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let store = try makeStore(container)
        let two = try photos(2)
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Two", photos: two))

        let updated = try XCTUnwrap(store.removePhoto(id: two[0].id, fromMemoID: memo.id))

        XCTAssertEqual(updated.photoIDs, [two[1].id])
        XCTAssertEqual(store.memos, [updated])
        XCTAssertNil(store.photoData(forPhotoID: two[0].id))
        XCTAssertEqual(try photoRecordCount(container), 1)
    }

    func testRemovingAPhotoTheMemoDoesNotHaveDoesNothing() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let mine = try photo()
        let other = try photo()
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Mine", photos: [mine]))
        let another = try XCTUnwrap(store.addWrittenMemo(text: "Other", photos: [other]))

        XCTAssertNil(store.removePhoto(id: other.id, fromMemoID: memo.id))
        XCTAssertNil(store.removePhoto(id: mine.id, fromMemoID: UUID()))

        XCTAssertEqual(store.memo(id: memo.id)?.photoIDs, [mine.id])
        XCTAssertEqual(store.memo(id: another.id)?.photoIDs, [other.id])
    }

    func testRemovingTheLastPhotoOfAMemoWithTextLeavesAnOrdinaryWrittenMemo() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let one = try photo()
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Words", photos: [one]))

        let updated = try XCTUnwrap(store.removePhoto(id: one.id, fromMemoID: memo.id))

        XCTAssertEqual(updated.photoCount, 0)
        XCTAssertEqual(updated.title, "Words")
        XCTAssertNil(store.closeMemo(id: memo.id))
    }

    // MARK: Discard rules

    func testEmptyingAWrittenMemosTextKeepsItAsAPhotoMemoWhenItHasPhotos() throws {
        let store = try makeStore(try KyoModelContainer.make(inMemory: true))
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Words", photos: try photos(1)))

        let edited = try XCTUnwrap(store.editMemo(id: memo.id, text: ""))
        XCTAssertNil(store.closeMemo(id: memo.id))

        XCTAssertEqual(edited.title, "Photo memo")
        XCTAssertEqual(store.memos.map(\.title), ["Photo memo"])
        XCTAssertNotNil(store.memo(id: memo.id))
    }

    func testAMemoWithNeitherTextNorPhotosIsDiscardedWhenClosed() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let store = try makeStore(container)
        let one = try photo()
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "", photos: [one]))

        _ = store.removePhoto(id: one.id, fromMemoID: memo.id)
        // Still open: kept until it's closed, like emptying the text.
        XCTAssertEqual(store.memos.count, 1)
        let discarded = store.closeMemo(id: memo.id)

        XCTAssertEqual(discarded?.id, memo.id)
        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<MemoRecord>()), 0)
        XCTAssertEqual(try photoRecordCount(container), 0)
    }

    func testAPhotoMemoSurvivesTheLaunchPurgeButAnEmptiedOneDoesNot() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let store = try makeStore(container)
        let photoMemo = try XCTUnwrap(store.addWrittenMemo(text: "Words", photos: try photos(2)))
        _ = store.editMemo(id: photoMemo.id, text: "")
        let one = try photo()
        let emptied = try XCTUnwrap(store.addWrittenMemo(text: "", photos: [one]))
        _ = store.removePhoto(id: one.id, fromMemoID: emptied.id)
        let words = try XCTUnwrap(store.addWrittenMemo(text: "Still here"))
        let wordsEmptied = try XCTUnwrap(store.addWrittenMemo(text: "Soon empty"))
        _ = store.editMemo(id: wordsEmptied.id, text: "")

        let relaunched = try makeStore(container)

        XCTAssertEqual(relaunched.memo(id: photoMemo.id)?.title, "Photo memo")
        XCTAssertEqual(relaunched.memo(id: photoMemo.id)?.photoCount, 2)
        XCTAssertNil(relaunched.memo(id: emptied.id))
        XCTAssertNil(relaunched.memo(id: wordsEmptied.id))
        XCTAssertNotNil(relaunched.memo(id: words.id))
        XCTAssertEqual(try photoRecordCount(container), 2)
    }

    // MARK: Delete

    func testDeletingAMemoRemovesItsPhotos() throws {
        let container = try KyoModelContainer.make(inMemory: true)
        let store = try makeStore(container)
        let two = try photos(2)
        let memo = try XCTUnwrap(store.addWrittenMemo(text: "Doomed", photos: two))
        let kept = try photo()
        _ = store.addWrittenMemo(text: "Kept", photos: [kept])

        _ = store.deleteMemo(id: memo.id)

        XCTAssertNil(store.photoData(forPhotoID: two[0].id))
        XCTAssertNil(store.thumbnailData(forPhotoID: two[1].id))
        XCTAssertEqual(try photoRecordCount(container), 1)
        XCTAssertEqual(store.photoData(forPhotoID: kept.id), kept.data)
    }

    // MARK: Voice memos

    private struct Recording {
        let container: ModelContainer
        let recorder: FakeAudioRecorder
        let store: MemoStore
        let session: VoiceRecordingSession
    }

    private func makeRecording() throws -> Recording {
        let container = try KyoModelContainer.make(inMemory: true)
        let recorder = FakeAudioRecorder()
        let clock = try moment(29)
        let store = MemoStore(modelContainer: container, now: { clock }, calendar: calendar)
        let session = VoiceRecordingSession(recorder: recorder, memos: store, now: { clock })
        return Recording(container: container, recorder: recorder, store: store, session: session)
    }

    func testPhotosTakenWhileRecordingAreSavedWithTheVoiceMemo() async throws {
        let r = try makeRecording()
        await r.session.begin()
        let first = try photo()
        let second = try photo()

        XCTAssertTrue(r.session.addPhoto(first))
        XCTAssertTrue(r.session.addPhoto(second))
        r.session.removePhoto(id: first.id)
        r.session.stop()

        guard case .saved(let memo, _)? = r.session.outcome else { return XCTFail("Expected a saved voice memo") }
        XCTAssertEqual(memo.kind, .voice)
        XCTAssertEqual(memo.photoIDs, [second.id])
        XCTAssertEqual(memo.title, "Voice memo")
        XCTAssertEqual(r.store.photoData(forPhotoID: second.id), second.data)
        XCTAssertNil(r.store.photoData(forPhotoID: first.id))
    }

    func testDiscardingARecordingDropsItsPhotos() async throws {
        let r = try makeRecording()
        await r.session.begin()
        r.session.addPhoto(try photo())

        r.session.discard()

        XCTAssertTrue(r.session.photos.isEmpty)
        XCTAssertTrue(r.store.memos.isEmpty)
        XCTAssertEqual(try photoRecordCount(r.container), 0)
    }

    func testARecordingTakesAtMostFourPhotos() async throws {
        let r = try makeRecording()
        await r.session.begin()

        for _ in 0..<4 { XCTAssertTrue(r.session.addPhoto(try photo())) }
        XCTAssertFalse(r.session.addPhoto(try photo()))
        r.session.stop()

        XCTAssertEqual(r.store.memos.first?.photoCount, 4)
    }

    func testAVoiceMemoCanGainAndLosePhotosAfterwardsAndIsNeverDiscardedForHavingNoneOrNoText() async throws {
        let r = try makeRecording()
        await r.session.begin()
        r.session.stop()
        let id = try XCTUnwrap(r.store.memos.first?.id)
        let one = try photo()

        let withPhoto = try XCTUnwrap(r.store.addPhoto(one, toMemoID: id))
        XCTAssertEqual(withPhoto.photoIDs, [one.id])
        XCTAssertEqual(withPhoto.title, "Voice memo")

        _ = r.store.removePhoto(id: one.id, fromMemoID: id)
        XCTAssertNil(r.store.closeMemo(id: id))
        XCTAssertNotNil(r.store.memo(id: id))
    }

    func testDeletingAVoiceMemoRemovesItsPhotosAndAudio() async throws {
        let r = try makeRecording()
        await r.session.begin()
        r.session.addPhoto(try photo())
        r.session.stop()
        let id = try XCTUnwrap(r.store.memos.first?.id)

        _ = r.store.deleteMemo(id: id)

        XCTAssertEqual(try photoRecordCount(r.container), 0)
        XCTAssertEqual(try r.container.mainContext.fetchCount(FetchDescriptor<MemoAudioRecord>()), 0)
    }
}
