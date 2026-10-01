import Foundation

/// The latest encoded payload for each key published through `WCSession.applicationContext`.
///
/// `updateApplicationContext` replaces the whole context dictionary, so every snapshot kind
/// (task, and later habit — see `docs/adr/0003-habit-sync.md`) must be written together or a
/// write for one kind would erase the others. Each kind sets its payload here; the transport
/// always writes `context` in a single update.
struct ApplicationContextEntries: Equatable, Sendable {
    private var payloads: [String: Data] = [:]

    /// Replaces the latest payload for `key`, leaving every other key untouched.
    mutating func set(_ payload: Data, forKey key: String) {
        payloads[key] = payload
    }

    /// Every key's latest payload, ready for a single `updateApplicationContext` call.
    var context: [String: Any] {
        payloads.mapValues { $0 as Any }
    }

    var isEmpty: Bool { payloads.isEmpty }
}
