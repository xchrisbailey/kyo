import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text("Hello, Kyo")
                    .font(.title2.bold())

                Text("Make today yours.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Kyo")
        }
    }
}

#Preview {
    ContentView()
}
