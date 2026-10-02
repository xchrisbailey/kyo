import AppIntents

/// **Record memo**: brings Kyo to the front, opens the recorder and starts recording. Run by the
/// Control Center / Lock Screen control, the Action button, Siri, Shortcuts and Spotlight.
///
/// `.foreground(.immediate)` has the system bring the app forward before `perform()` runs, so the
/// recorder can start. `allowedExecutionTargets = .main` keeps `perform()` in the app process even
/// though the control's extension compiles this intent too; the router only exists in the app.
struct RecordMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Record memo"
    static let description = IntentDescription("Opens Kyo and starts recording a voice memo.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let allowedExecutionTargets: ExecutionTargets = .main
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCaptureRouter.shared.perform(.recordMemo)
        return .result()
    }
}

/// **Write memo**: brings Kyo to the front and opens the compose sheet.
struct WriteMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Write memo"
    static let description = IntentDescription("Opens Kyo and starts a written memo.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let allowedExecutionTargets: ExecutionTargets = .main
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCaptureRouter.shared.perform(.writeMemo)
        return .result()
    }
}
