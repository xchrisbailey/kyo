import Foundation
import SwiftData

#if os(iOS)
import UIKit
/// Only this adapter talks to iCloud; tests provide a controllable external boundary.
@MainActor
final class UbiquitousProjectsPreferenceCloud: ProjectsPreferenceCloud {
    private let store: NSUbiquitousKeyValueStore
    private var observer: NSObjectProtocol?
    private var handler: (@MainActor () -> Void)?

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handler?() }
        }
    }

    func read() -> Data? { store.data(forKey: ProjectsPreferenceStore.storageKey) }
    func write(_ data: Data) {
        store.set(data, forKey: ProjectsPreferenceStore.storageKey)
        store.synchronize()
    }
    func synchronize() { store.synchronize() }
    func setChangeHandler(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
}
/// A UI launch can receive a peer's explicit choice after a deterministic background/foreground
/// cycle, exercising the actual preference reconciliation without iCloud or a timer.
@MainActor
private final class BackgroundProjectsPreferenceCloud: ProjectsPreferenceCloud {
    private var data: Data?
    private var shouldDeliver = false
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.shouldDeliver = true }
        }
    }

    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func setChangeHandler(_ handler: @escaping @MainActor () -> Void) {}
    func synchronize() {
        guard shouldDeliver else { return }
        shouldDeliver = false
        let previous = data.flatMap { try? JSONDecoder().decode(ProjectsPreferenceRecord.self, from: $0) }
        data = try? JSONEncoder().encode(ProjectsPreferenceRecord(version: 1,
            isEnabled: false, isExplicit: true, timestamp: (previous?.timestamp ?? 0) + 1,
            deviceID: "ui-test-peer", recordID: UUID().uuidString))
    }
}

#endif

/// One preference for every window. Isolated launches never construct a cloud adapter.
@MainActor
enum ProjectsPreferenceSelection {
    static let disableAfterBackgroundEnvironmentKey = "KYO_PROJECTS_DISABLE_AFTER_BACKGROUND"
    static let enabledEnvironmentKey = "KYO_PROJECTS_ENABLED"
    static let suiteEnvironmentKey = "KYO_PROJECTS_PREFERENCE_SUITE"
    private static var shared: ProjectsPreferenceStore?

    #if os(iOS)
    static func make(modelContainer: ModelContainer) -> ProjectsPreferenceStore {
        if let shared { return shared }
        let environment = ProcessInfo.processInfo.environment
        let isolated = KyoModelContainer.isInMemoryRequested(in: environment)
            || environment[suiteEnvironmentKey] != nil
        let defaults: UserDefaults
        if isolated {
            defaults = UserDefaults(suiteName: environment[suiteEnvironmentKey]
                ?? "kyo.projectsPreference.ui-tests.\(UUID().uuidString)")!
        } else {
            defaults = .standard
        }
        let cloud: (any ProjectsPreferenceCloud)? = isolated
            ? (environment[disableAfterBackgroundEnvironmentKey] == "1" ? BackgroundProjectsPreferenceCloud() : nil)
            : UbiquitousProjectsPreferenceCloud()
        let store = ProjectsPreferenceStore(modelContainer: modelContainer, defaults: defaults,
            cloud: cloud,
            transport: isolated ? nil : WatchConnectivityTaskTransport.shared)
        if isolated, let enabled = environment[enabledEnvironmentKey] { store.setEnabled(enabled == "1") }
        shared = store
        return store
    }
    #endif

    static func makeWatch() -> WatchProjectsPreferenceStore {
        let environment = ProcessInfo.processInfo.environment
        if KyoModelContainer.isInMemoryRequested(in: environment) || environment[suiteEnvironmentKey] != nil {
            let defaults = UserDefaults(suiteName: environment[suiteEnvironmentKey]
                ?? "kyo.watchProjectsPreference.ui-tests.\(UUID().uuidString)")!
            let store = WatchProjectsPreferenceStore(defaults: defaults)
            if let enabled = environment[enabledEnvironmentKey] {
                store.receive(WatchProjectsPreference(revision: Int64.max, isEnabled: enabled == "1"))
            }
            return store
        }
        return WatchProjectsPreferenceStore(transport: WatchConnectivityTaskTransport.shared)
    }
}
