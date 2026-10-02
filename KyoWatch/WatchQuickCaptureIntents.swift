import AppIntents

/// **Record memo** on the Watch: brings Kyo on the Watch to the front, opens the recorder and
/// starts recording. Run by the Watch's Record memo control (Control Center, the Smart Stack and
/// the Action button). Voice only: the Watch has no written memo and no Siri phrase.
///
/// It's a separate intent from the iPhone's `RecordMemoIntent` because iPhone controls that open
/// the iPhone app don't appear on the Watch, and this one has to run on the Watch.
/// `.foreground(.immediate)` has the system bring the Watch app forward before `perform()` runs.
/// `allowedExecutionTargets = .main` keeps `perform()` in the Watch app process even though the
/// control's extension compiles this intent too; the router only exists in the app. The recording
/// happens on the Watch, so it works with the phone out of reach.
struct WatchRecordMemoIntent: AppIntent {
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
