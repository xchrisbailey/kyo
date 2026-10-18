import Combine
import Foundation
import SwiftData

@MainActor
protocol ProjectsPreferenceBehavior: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

/// An explicit user choice always outranks an inferred upgrade, including a later upgrade.
struct ProjectsPreferenceRecord: Codable, Equatable, Sendable, Comparable {
    let version: Int
    let isEnabled: Bool
    let isExplicit: Bool
    let timestamp: Int64
    let deviceID: String
    let recordID: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.isExplicit != rhs.isExplicit { return !lhs.isExplicit }
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        return lhs.recordID < rhs.recordID
    }
}

/// The external iCloud boundary. A write requests synchronization; delivery is asynchronous.
@MainActor
protocol ProjectsPreferenceCloud: AnyObject {
    func read() -> Data?
    func write(_ data: Data)
    func setChangeHandler(_ handler: @escaping @MainActor () -> Void)
    func synchronize()
}

struct WatchProjectsPreference: Codable, Equatable, Sendable {
    let revision: Int64
    let isEnabled: Bool
}

@MainActor
protocol ProjectsPreferenceTransport: AnyObject {
    func publish(projectsPreference: WatchProjectsPreference)
    func setProjectsPreferenceHandler(_ handler: @escaping @MainActor (WatchProjectsPreference) -> Void)
}

@MainActor
final class ProjectsPreferenceStore: ObservableObject, ProjectsPreferenceBehavior {
    static let storageKey = "kyo.projectsPreference.v1"
    static let deviceStorageKey = "kyo.projectsPreferenceDevice.v1"
    static let revisionStorageKey = "kyo.projectsPreferenceRevision.v1"
    @Published private(set) var isEnabled: Bool
    private var record: ProjectsPreferenceRecord?
    private var revision: Int64
    private let defaults: UserDefaults
    private let cloud: (any ProjectsPreferenceCloud)?
    private let transport: (any ProjectsPreferenceTransport)?
    private let now: () -> Date
    private let deviceID: String

    init(defaults: UserDefaults = .standard, hasExistingProjects: Bool = false,
         cloud: (any ProjectsPreferenceCloud)? = nil,
         transport: (any ProjectsPreferenceTransport)? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.cloud = cloud
        self.transport = transport
        self.now = now
        deviceID = defaults.string(forKey: Self.deviceStorageKey) ?? UUID().uuidString
        defaults.set(deviceID, forKey: Self.deviceStorageKey)
        record = Self.decode(defaults.data(forKey: Self.storageKey))
        isEnabled = record?.isEnabled ?? false
        revision = (defaults.object(forKey: Self.revisionStorageKey) as? NSNumber)?.int64Value ?? 0
        // Reconcile before migration so an explicit cloud choice cannot be replaced by inference.
        reconcile()
        if record == nil && hasExistingProjects {
            accept(makeRecord(enabled: true, explicit: false))
            reconcile()
        }
        publishToWatch()
        cloud?.setChangeHandler { [weak self] in self?.reconcile() }
        cloud?.synchronize()
    }

    convenience init(modelContainer: ModelContainer, defaults: UserDefaults = .standard,
                     cloud: (any ProjectsPreferenceCloud)? = nil,
                     transport: (any ProjectsPreferenceTransport)? = nil) {
        let hasProjects = ((try? modelContainer.mainContext.fetchCount(FetchDescriptor<ProjectRecord>())) ?? 0) > 0
        self.init(defaults: defaults, hasExistingProjects: hasProjects, cloud: cloud, transport: transport)
    }

    func setEnabled(_ enabled: Bool) {
        accept(makeRecord(enabled: enabled, explicit: true))
        reconcile()
        publishToWatch()
    }

    /// Also called on foreground activation, after time offline or an iCloud-account change.
    func refresh() {
        cloud?.synchronize()
        reconcile()
    }

    private func makeRecord(enabled: Bool, explicit: Bool) -> ProjectsPreferenceRecord {
        ProjectsPreferenceRecord(version: 1, isEnabled: enabled, isExplicit: explicit,
            timestamp: max((record?.timestamp ?? 0) + 1, Int64(now().timeIntervalSince1970 * 1000)),
            deviceID: deviceID, recordID: UUID().uuidString)
    }

    private static func decode(_ data: Data?) -> ProjectsPreferenceRecord? {
        guard let data, let record = try? JSONDecoder().decode(ProjectsPreferenceRecord.self, from: data),
              record.version == 1 else { return nil }
        return record
    }

    private func accept(_ winner: ProjectsPreferenceRecord) {
        record = winner
        defaults.set(try? JSONEncoder().encode(winner), forKey: Self.storageKey)
        isEnabled = winner.isEnabled
    }

    private func reconcile() {
        let remoteData = cloud?.read()
        if let remote = Self.decode(remoteData), record == nil || record! < remote {
            accept(remote)
            publishToWatch()
        }
        // A default never publishes to iCloud. Repair a stale remote value with the known winner.
        if let record, let data = try? JSONEncoder().encode(record), Self.decode(remoteData) != record {
            cloud?.write(data)
        }
    }

    private func publishToWatch() {
        revision = max(revision + 1, Int64(now().timeIntervalSince1970 * 1000))
        defaults.set(NSNumber(value: revision), forKey: Self.revisionStorageKey)
        transport?.publish(projectsPreference: WatchProjectsPreference(revision: revision, isEnabled: isEnabled))
    }
}

@MainActor
final class WatchProjectsPreferenceStore: ObservableObject {
    static let storageKey = "kyo.watchProjectsPreference.v1"
    @Published private(set) var isEnabled: Bool
    private var state: WatchProjectsPreference?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, transport: (any ProjectsPreferenceTransport)? = nil) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(WatchProjectsPreference.self, from: $0) }
        // An older phone has no preference. Preserve its project presentation and task access.
        isEnabled = state?.isEnabled ?? true
        transport?.setProjectsPreferenceHandler { [weak self] in self?.receive($0) }
    }

    func receive(_ incoming: WatchProjectsPreference) {
        guard state == nil || incoming.revision > state!.revision else { return }
        defaults.set(try? JSONEncoder().encode(incoming), forKey: Self.storageKey)
        state = incoming
        isEnabled = incoming.isEnabled
    }
}
