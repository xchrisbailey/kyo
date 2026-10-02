import Foundation
import SwiftData

/// One of a **Memo**'s photos, on its own model so listing and searching memos never loads the
/// bytes (docs/adr/0004). `data` is `.externalStorage`, the relationship to its memo is optional
/// with its inverse set, and nothing here is unique, per the ADR's CloudKit rules.
@Model
final class MemoPhotoRecord {
    var id: UUID = UUID()
    /// Where the photo sits among its memo's photos: ascending, in the order they were added. A
    /// removed photo leaves a gap, which is harmless.
    var order: Int = 0
    /// HEIC, longest edge at most 2048 px. The original isn't kept.
    @Attribute(.externalStorage) var data: Data?
    /// A small JPEG kept inline, so rows can show the photo without reading `data`.
    var thumbnail: Data?
    var memo: MemoRecord?

    init(id: UUID = UUID(), order: Int, data: Data, thumbnail: Data) {
        self.id = id
        self.order = order
        self.data = data
        self.thumbnail = thumbnail
    }
}
