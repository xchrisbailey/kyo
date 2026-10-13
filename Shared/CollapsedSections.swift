import Foundation

/// One of the titled groups Today is divided into. The watch has no Schedule section and ignores that one.
enum TodaySectionID: String, CaseIterable, Sendable {
    case schedule
    case tasks
    case projects
    case habits
    case memos
}

/// Which **sections** on Today are collapsed to their header.
///
/// The state is kept in the device's own `UserDefaults`, so each device remembers its own layout.
/// It isn't synced and isn't tied to a day. Every section is expanded until the user collapses it.
@MainActor
final class CollapsedSections: ObservableObject {
    static let storageKey = "kyo.collapsedSections"
    static let projectStorageKey = "kyo.collapsedProjects.v1"
    static let completedStorageKey = "kyo.collapsedProjectCompleted.v1"

    @Published private(set) var collapsed: Set<TodaySectionID>
    @Published private var collapsedProjects: Set<UUID>
    @Published private var collapsedCompleted: Set<UUID>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        collapsedProjects = Set((defaults.stringArray(forKey: Self.projectStorageKey) ?? []).compactMap(UUID.init(uuidString:)))
        collapsedCompleted = Set((defaults.stringArray(forKey: Self.completedStorageKey) ?? []).compactMap(UUID.init(uuidString:)))
        let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
        collapsed = Set(stored.compactMap(TodaySectionID.init(rawValue:)))
    }

    func isProjectCollapsed(_ projectID: UUID) -> Bool { collapsedProjects.contains(projectID) }
    func isCompletedCollapsed(_ projectID: UUID) -> Bool { collapsedCompleted.contains(projectID) }

    func toggleProject(_ projectID: UUID) {
        if !collapsedProjects.insert(projectID).inserted { collapsedProjects.remove(projectID) }
        defaults.set(collapsedProjects.map(\.uuidString).sorted(), forKey: Self.projectStorageKey)
    }

    func toggleCompleted(_ projectID: UUID) {
        if !collapsedCompleted.insert(projectID).inserted { collapsedCompleted.remove(projectID) }
        defaults.set(collapsedCompleted.map(\.uuidString).sorted(), forKey: Self.completedStorageKey)
    }

    func isCollapsed(_ section: TodaySectionID) -> Bool {
        collapsed.contains(section)
    }

    /// Collapses an expanded section, or expands a collapsed one.
    func toggle(_ section: TodaySectionID) {
        if collapsed.contains(section) {
            collapsed.remove(section)
        } else {
            collapsed.insert(section)
        }
        persist()
    }

    /// Starting a task draft expands a collapsed Tasks section, so the user can see what they type.
    /// The expansion is remembered. No other action expands a section.
    func startTaskDraft() {
        guard collapsed.contains(.tasks) else { return }
        collapsed.remove(.tasks)
        persist()
    }

    private func persist() {
        defaults.set(collapsed.map(\.rawValue).sorted(), forKey: Self.storageKey)
    }
}
