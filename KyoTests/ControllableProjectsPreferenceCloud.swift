import Foundation

/// A device's last-delivered iCloud value, independent of when a peer publishes its next one.
@MainActor
final class ControllableProjectsPreferenceCloud: ProjectsPreferenceCloud {
    private(set) var data: Data?
    private var handler: (@MainActor () -> Void)?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func synchronize() {}
    func setChangeHandler(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    func deliver(_ data: Data?) {
        self.data = data
        handler?()
    }
}
