import SwiftData
import SwiftUI

@main
struct KyoApp: App {
    /// Opened once at launch and reused for the life of the app. `.failure` shows the blocking
    /// open-failure screen; Kyo never substitutes an empty store for one it couldn't open.
    @State private var storeResult = KyoApp.openStore()

    var body: some Scene {
        WindowGroup {
            switch storeResult {
            case .success(let container):
                TodayView(modelContainer: container)
            case .failure:
                StoreOpenFailedView {
                    storeResult = KyoApp.openStore()
                }
            }
        }
    }

    private static func openStore() -> Result<ModelContainer, Error> {
        Result { try KyoModelContainer.make(inMemory: KyoModelContainer.isInMemoryRequested) }
    }
}

private struct StoreOpenFailedView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Kyo couldn't open your data")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Your tasks and habits haven't been changed. Try again, and restart your device if this keeps happening.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
