import SwiftUI
import UIKit

/// The full-screen recorder behind **+ > Voice memo**: the elapsed time and a waveform, with
/// **Discard** (saves nothing) and **Stop** (saves). Shows the 10-minute cap warning, **Paused**
/// with **Resume** and **Stop** after an interruption, and the denied-microphone state. Up to 4
/// photos can be attached while recording; they're saved with the memo on **Stop**.
struct VoiceRecorderView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var session: VoiceRecordingSession
    let onFinish: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Voice memo")
                    .headerStyle(.navigationTitle)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            }
            .accessibilityAddTraits(.isHeader)

            switch session.phase {
            case .microphoneDenied:
                unavailable(
                    message: "Kyo needs microphone access to record",
                    showsSettings: true
                )
            case .couldNotRecord:
                unavailable(message: "Kyo couldn't start recording", showsSettings: false)
            case .idle, .starting, .recording, .paused:
                recorder
            }
        }
        .padding(24)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedText()
        .background(theme.screenBackground.ignoresSafeArea())
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
            // A tap at the first moment of recording; resuming from Paused has none.
            if oldPhase == .starting, phase == .recording {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .onChange(of: session.outcome) { _, outcome in
            guard let outcome else { return }
            if case .saved(_, reachedCap: true) = outcome {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    if session.phase == .paused {
                        Image(systemName: "pause.fill")
                            .foregroundStyle(theme.warning)
                            .accessibilityHidden(true)
                        Text("Paused")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.warning)
                    } else {
                        Circle()
                            .fill(theme.destructive)
                            .frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 28)
                Text(Memo.formattedDuration(session.elapsed))
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("\(session.phase == .paused ? "Paused" : "Recording"), \(Memo.formattedDuration(session.elapsed))")
                if session.isNearCap {
                    Label("Ends in \(Memo.formattedDuration(session.remaining))", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.onWarning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.warning, in: Capsule())
                        .accessibilityLabel("Recording ends in \(Int(session.remaining.rounded(.up))) seconds")
                }
            }

            WaveformView(levels: session.levels, isPaused: session.phase != .recording)
                .frame(height: 72)
                .accessibilityHidden(true)

            liveTranscript

            MemoPendingPhotos(
                photos: session.photos,
                onAdd: { photo in session.addPhoto(photo) },
                onRemove: { id in session.removePhoto(id: id) }
            )

            controls
        }
        .frame(maxHeight: .infinity)
    }

    /// The large live transcript, or the note that it will come after recording.
    private var liveTranscript: some View {
        ScrollView {
            Text(liveTranscriptText)
                .font(.title3)
                .foregroundStyle(session.liveTranscript.isEmpty ? theme.secondaryText : theme.primaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(liveTranscriptAccessibilityLabel)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: .infinity)
    }

    private var liveTranscriptText: String {
        switch session.liveStatus {
        case .unavailable: "Transcript will appear after recording"
        case .starting, .listening: session.liveTranscript.isEmpty ? "Listening…" : session.liveTranscript
        }
    }

    private var liveTranscriptAccessibilityLabel: String {
        session.liveTranscript.isEmpty ? liveTranscriptText : "Live transcript: \(session.liveTranscript)"
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                session.discard()
            } label: {
                Label("Discard", systemImage: "trash")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.destructive)
                    .frame(minWidth: 110, minHeight: 52)
                    .padding(.horizontal, 6)
                    .background(theme.destructive.opacity(0.12), in: Capsule())
                    .contentShape(Capsule())
            }
            .disabled(!session.isActive)
            .accessibilityHint("Throws this recording away")

            if session.phase == .paused {
                Button {
                    Task { await session.resume() }
                } label: {
                    Label("Resume", systemImage: "mic.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .frame(minWidth: 110, minHeight: 52)
                        .padding(.horizontal, 6)
                        .background(theme.accent.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
            }

            Button {
                session.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.onDestructive)
                    .frame(minWidth: 110, minHeight: 52)
                    .padding(.horizontal, 6)
                    .background(theme.destructive, in: Capsule())
                    .contentShape(Capsule())
            }
            .disabled(!session.isActive)
            .accessibilityHint("Saves this recording as a voice memo")
        }
        .buttonStyle(.plain)
    }

    // MARK: Unavailable

    private func unavailable(message: String, showsSettings: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: "mic.slash")
                .font(.system(size: 44))
                .foregroundStyle(theme.secondaryText)
                .accessibilityHidden(true)
            Text(message)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if showsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
            Button("Close", action: onFinish)
                .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Recent input levels as bars, newest at the right. Empty slots on the left stay flat.
private struct WaveformView: View {
    @Environment(\.theme) private var theme
    let levels: [Float]
    let isPaused: Bool

    var body: some View {
        let padded = Array(repeating: Float(0), count: max(0, VoiceRecordingSession.waveformLength - levels.count)) + levels
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill((isPaused ? theme.secondaryText : theme.accent).opacity(0.35 + 0.65 * Double(level)))
                        .frame(height: max(4, geometry.size.height * CGFloat(level)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
