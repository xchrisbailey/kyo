import Foundation
import SwiftData

/// The stored form of a `Memo` on the phone and iPad. Follows docs/adr/0004: no unique
/// constraints (duplicates are removed by id in app code), every attribute has a default or is
/// optional, and the schema only ever grows. The day is stored as flat integer fields matching
/// `TaskCompletionDay`, never as a timestamp.
///
/// Later tickets add to this model without reshaping it: a voice memo's title, duration,
/// transcript state and cap note as new optional fields, and its audio and photos as separate
/// models with `.externalStorage` data, attached through optional relationships with inverses.
@Model
final class MemoRecord {
    var id: UUID = UUID()
    /// `Memo.Kind.rawValue`, stored as a string so a later kind needs no migration.
    var kindRaw: String = Memo.Kind.written.rawValue
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var dayEra: Int?
    var dayYear: Int = 0
    var dayMonth: Int = 0
    var dayDay: Int = 0
    var text: String = ""

    init(id: UUID = UUID(), kind: Memo.Kind, createdAt: Date, day: TaskCompletionDay, text: String) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.dayEra = day.era
        self.dayYear = day.year
        self.dayMonth = day.month
        self.dayDay = day.day
        self.text = text
    }

    var kind: Memo.Kind {
        Memo.Kind(rawValue: kindRaw) ?? .written
    }

    var day: TaskCompletionDay {
        TaskCompletionDay(era: dayEra, year: dayYear, month: dayMonth, day: dayDay)
    }

    var memo: Memo {
        Memo(id: id, kind: kind, createdAt: createdAt, day: day, text: text)
    }
}
