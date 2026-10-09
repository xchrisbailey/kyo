import SwiftUI
import WatchKit

/// The Watch's full-screen recorder behind the Memos section's **Record** button: the elapsed
/// time and a level meter, with **Discard** (saves nothing) and **Stop** (saves). Shows the
/// 10-minute cap warning, **Paused** with **Resume** and **Stop** after an interruption, and the
/// microphone-denied and out-of-space messages. There's no live transcript: the phone
/// transcribes the recording.
struct WatchRecorderView: View {
    @ObservedObject var session: VoiceRecordingSession
    let onFinish: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.watchPalette) private var palette

    var body: some View {
        Group {
            switch session.phase {
            case .microphoneDenied:
                unavailable("Kyo needs microphone access. Turn it on in Settings on Apple Watch.")
            case .couldNotRecord:
                unavailable(session.failure == .outOfSpace ? "Not enough space on Apple Watch" : "Kyo couldn't start recording")
            case .idle, .starting, .recording, .paused:
                recorder
            }
        }
        .interactiveDismissDisabled()
        .task {
            await session.begin()
            while !Task.isCancelled {
                session.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            session.tick()
            // Back from Settings with access allowed: start recording.
            if session.phase == .microphoneDenied {
                Task { await session.begin() }
            }
        }
        .onChange(of: session.phase) { oldPhase, phase in
            // At the first moment of recording; resuming from Paused has none.
            if oldPhase == .starting, phase == .recording {
                WKInterfaceDevice.current().play(.start)
            }
        }
        .onChange(of: session.isNearCap) { _, isNearCap in
            if isNearCap { WKInterfaceDevice.current().play(.notification) }
        }
        .onChange(of: session.outcome) { _, outcome in
            guard let outcome else { return }
            if case .saved = outcome {
                WKInterfaceDevice.current().play(.success)
            }
            onFinish()
        }
        .onDisappear {
            // Never lose a recording that's still running.
            if session.isActive { session.stop() }
        }
    }

    // MARK: Recording

    private var recorder: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                if session.phase == .paused {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(palette.warning.style)
                        .accessibilityHidden(true)
                    Text("Paused")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.warning.style)
                } else {
                    Circle()
                        .fill(palette.destructive.style)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("Recording")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryText.style)
                }
            }
            Text(Memo.formattedDuration(session.elapsed))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("\(session.phase == .paused ? "Paused" : "Recording"), \(Memo.formattedDuration(session.elapsed))")
            if session.isNearCap {
                Label("Ends in \(Memo.formattedDuration(session.remaining))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.warning.style)
                    .accessibilityLabel("Recording ends in \(Int(session.remaining.rounded(.up))) seconds")
            } else {
                WatchLevelMeter(levels: session.levels, isPaused: session.phase != .recording)
                    .frame(height: 22)
                    .accessibilityHidden(true)
            }
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                session.discard()
            } label: {
                Image(systemName: "trash")
                    .frame(maxWidth: .infinity)
            }
            .solidFill(.destructive)
            .accessibilityLabel("Discard")
            .accessibilityHint("Stops and saves nothing")

            if session.phase == .paused {
                Button {
                    Task { await session.resume() }
                } label: {
                    Image(systemName: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .solidFill(.warning)
                .accessibilityLabel("Resume")
            }

            Button {
                session.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .solidFill(.accent)
            .accessibilityLabel("Stop")
            .accessibilityHint("Stops and saves the recording")
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 2)
    }

    // MARK: Unavailable

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.slash")
                .font(.title3)
                .foregroundStyle(palette.secondaryText.style)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("OK", action: onFinish)
        }
    }
}

/// A simple level meter: the recent input levels as a row of bars, newest on the right.
private struct WatchLevelMeter: View {
    let levels: [Float]
    let isPaused: Bool
    @Environment(\.watchPalette) private var palette

    private static let barCount = 24

    var body: some View {
        let recent = Array(levels.suffix(Self.barCount))
        let padded = Array(repeating: Float(0), count: Self.barCount - recent.count) + recent
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(isPaused ? palette.secondaryText.color : palette.accent.color)
                        .frame(height: max(3, CGFloat(level) * geometry.size.height))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
