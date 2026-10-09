import SwiftData
import SwiftUI

@main
struct KyoApp: App {
    /// Opened once at launch and reused for the life of the app. `.failure` shows the blocking
    /// open-failure screen; Kyo never substitutes an empty store for one it couldn't open.
    @State private var storeResult = KyoApp.openStore()
    /// The one theme every window shows.
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                switch storeResult {
                case .success(let container):
                    TodayView(modelContainer: container)
                case .failure:
                    StoreOpenFailedView {
                        storeResult = KyoApp.openStore()
                    }
                }
            }
            .themedTint()
            .environment(\.theme, themeStore.current)
        }
    }

    /// Opens the store and, for the on-disk one, runs the one-time UserDefaults import before
    /// any list store exists. A failed import is invisible: the app carries on and the import
    /// is retried next launch.
    private static func openStore() -> Result<ModelContainer, Error> {
        let inMemory = KyoModelContainer.isInMemoryRequested
        return Result {
            let container = try KyoModelContainer.make(inMemory: inMemory)
            if !inMemory {
                UserDefaultsImport(modelContainer: container).run()
            }
            return container
        }
    }
}

private struct StoreOpenFailedView: View {
    @Environment(\.theme) private var theme
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(theme.secondaryText)
            Text("Kyo couldn't open your data")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Your tasks and habits haven't been changed. Try again, and restart your device if this keeps happening.")
                .font(.body)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(theme.onControlTint)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedText()
        .background(theme.screenBackground.ignoresSafeArea())
    }
}
