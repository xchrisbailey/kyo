import Foundation
import WatchConnectivity
import os

/// Carries `TaskListSnapshot`s between the phone and the Watch over `WCSession`'s
/// `applicationContext`, which keeps only the latest value delivered — a natural fit for
/// "latest wins" full-list sync. See docs/adr/0001-phone-authoritative-task-snapshots.md.
@MainActor
final class WatchConnectivityTaskTransport: NSObject, TaskSnapshotTransport, WCSessionDelegate {
    static let shared = WatchConnectivityTaskTransport()

    nonisolated static let snapshotKey = "hoy.taskSnapshot"

    private let session: WCSession?
    private let logger = Logger(subsystem: "com.example.hoy", category: "watch-sync")
    private var latestOutgoing: TaskListSnapshot?
    private var latestIncoming: TaskListSnapshot?
    private var handler: (@MainActor (TaskListSnapshot) -> Void)?

    private override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func publish(_ snapshot: TaskListSnapshot) {
        latestOutgoing = snapshot
        sendLatest()
    }

    func setSnapshotHandler(_ handler: @escaping @MainActor (TaskListSnapshot) -> Void) {
        self.handler = handler
        if let latestIncoming {
            handler(latestIncoming)
        }
    }

    private func sendLatest() {
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard let snapshot = latestOutgoing else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try session.updateApplicationContext([Self.snapshotKey: data])
            logger.log("published revision \(snapshot.revision) (\(snapshot.tasks.count) tasks)")
        } catch {
            logger.error("failed to publish snapshot: \(error.localizedDescription)")
        }
    }

    private func receive(data: Data) {
        guard let snapshot = try? JSONDecoder().decode(TaskListSnapshot.self, from: data) else { return }
        latestIncoming = snapshot
        handler?(snapshot)
        logger.log("received snapshot revision \(snapshot.revision) (\(snapshot.tasks.count) tasks)")
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let contextData = session.receivedApplicationContext[Self.snapshotKey] as? Data
        Task { @MainActor in
            self.sendLatest()
            if let contextData {
                self.receive(data: contextData)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.snapshotKey] as? Data else { return }
        Task { @MainActor in
            self.receive(data: data)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.sendLatest()
        }
    }
    #endif
}
