import AVFoundation
import SwiftUI

/// Plays a **Voice memo**'s stored audio for the open memo's pinned player.
@MainActor
final class MemoAudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var canPlay = false

    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    func load(_ data: Data?, fallbackDuration: TimeInterval) {
        stop()
        duration = fallbackDuration
        guard let data, let player = try? AVAudioPlayer(data: data) else {
            canPlay = false
            return
        }
        player.prepareToPlay()
        self.player = player
        duration = max(player.duration, 0)
        position = 0
        canPlay = true
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            progressTask?.cancel()
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if position >= duration { player.currentTime = 0 }
        guard player.play() else { return }
        isPlaying = true
        startReportingProgress()
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), duration)
        player?.currentTime = clamped
        position = clamped
    }

    /// Stops playback and releases the audio. The open memo calls this when it closes.
    func stop() {
        progressTask?.cancel()
        player?.stop()
        player = nil
        isPlaying = false
        position = 0
        canPlay = false
    }

    private func startReportingProgress() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let player = self.player else { return }
                if player.isPlaying {
                    self.position = player.currentTime
                } else if self.isPlaying {
                    // Played to the end.
                    self.isPlaying = false
                    self.position = self.duration
                    return
                } else {
                    return
                }
            }
        }
    }
}

/// The open Voice memo's player, pinned to the bottom of its card: play/pause and a scrubber.
struct MemoAudioPlayerBar: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale
    let loadAudio: () -> Data?
    let duration: TimeInterval

    @StateObject private var player = MemoAudioPlayer()
    @State private var isScrubbing = false
    @State private var scrubPosition: TimeInterval = 0

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.onAccentText)
                    .frame(width: 44, height: 44)
                    .background(theme.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!player.canPlay)
            .opacity(player.canPlay ? 1 : 0.4)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubPosition : player.position },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(player.duration, 1)
                ) { editing in
                    if editing {
                        scrubPosition = player.position
                    } else {
                        player.seek(to: scrubPosition)
                    }
                    isScrubbing = editing
                }
                .tint(theme.accent)
                .disabled(!player.canPlay)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(Memo.formattedDuration(shownPosition)) of \(Memo.formattedDuration(player.duration))")
                HStack {
                    Text(Memo.formattedDuration(shownPosition))
                    Spacer()
                    Text("-" + Memo.formattedDuration(max(0, player.duration - shownPosition)))
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(barStyle)
        .overlay(alignment: .top) { separator }
        .onAppear { player.load(loadAudio(), fallbackDuration: duration) }
        .onDisappear { player.stop() }
    }

    /// The theme's bar color, or the system material when it has none.
    private var barStyle: AnyShapeStyle {
        theme.barBackground.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.regularMaterial)
    }

    /// A line in the theme's separator color over its bar color; the system's divider over the material.
    @ViewBuilder
    private var separator: some View {
        if theme.barBackground != nil {
            Rectangle()
                .fill(theme.separator)
                .frame(height: 1 / displayScale)
        } else {
            Divider()
        }
    }

    private var shownPosition: TimeInterval {
        isScrubbing ? scrubPosition : player.position
    }
}
