import Foundation
import SwiftData

/// A **Voice memo**'s audio, on its own model so listing and searching memos never loads the
/// bytes (docs/adr/0004). The data is `.externalStorage`, the relationship to its memo is
/// optional with its inverse set, and nothing here is unique, per the ADR's CloudKit rules.
@Model
final class MemoAudioRecord {
    var id: UUID = UUID()
    /// AAC, mono, 48 kbps.
    @Attribute(.externalStorage) var data: Data?
    var memo: MemoRecord?

    init(id: UUID = UUID(), data: Data) {
        self.id = id
        self.data = data
    }
}
