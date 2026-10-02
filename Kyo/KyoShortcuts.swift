import AppIntents

/// The App Shortcuts Siri, Spotlight and the Shortcuts app show without any setup. Every phrase
/// includes the app name, which Siri also matches against its synonyms.
struct KyoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordMemoIntent(),
            phrases: [
                "Record a memo in \(.applicationName)",
                "New voice memo in \(.applicationName)",
            ],
            shortTitle: "Record memo",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: WriteMemoIntent(),
            phrases: [
                "Write a memo in \(.applicationName)",
                "New memo in \(.applicationName)",
            ],
            shortTitle: "Write memo",
            systemImageName: "square.and.pencil"
        )
    }
}
