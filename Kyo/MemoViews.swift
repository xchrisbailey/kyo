import SwiftUI
import UIKit

/// A row in Today's Memos section: the kind icon, the title, a detail line and the creation
/// time on the right (with the duration under it for a Voice memo). Tapping opens the memo;
/// swiping or long-pressing deletes it. The caller confirms before deleting a Voice memo.
struct MemoRow: View {
    let memo: Memo
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isDeleteRevealed = false

    private let deleteWidth: CGFloat = 84

    var body: some View {
        ZStack(alignment: .trailing) {
            rowContents
                .offset(x: isDeleteRevealed ? -deleteWidth : 0)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if value.translation.width < -40 {
                                withAnimation(.easeOut(duration: 0.2)) { isDeleteRevealed = true }
                            } else if value.translation.width > 40 {
                                withAnimation(.easeOut(duration: 0.2)) { isDeleteRevealed = false }
                            }
                        }
                )

            if isDeleteRevealed {
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: deleteWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete memo: \(memo.title)")
                .accessibilityHint("Deletes this memo permanently")
                .transition(.identity)
            }
        }
        .clipped()
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var rowContents: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: MemoPresentation.icon(for: memo.kind))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(KyoPalette.accent)
                    .frame(width: 28, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(memo.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if memo.transcriptState == .transcribing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Transcribing…")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if let detail = memo.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(MemoPresentation.time(memo.createdAt))
                    if memo.kind == .voice {
                        Text(Memo.formattedDuration(memo.duration))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(minHeight: 55)
            .frame(maxWidth: .infinity)
            .background(MemoPresentation.cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this memo")
        .accessibilityAction(named: "Delete", onDelete)
    }

    /// Kind, title and time, then the duration (Voice memo) and the detail line when there is
    /// one. A Voice memo's title is its kind name, so it's said once.
    private var accessibilityLabel: String {
        var parts = [MemoPresentation.kindName(for: memo.kind)]
        if memo.kind == .written { parts.append(memo.title) }
        parts.append(MemoPresentation.time(memo.createdAt))
        if memo.kind == .voice { parts.append(Memo.formattedDuration(memo.duration)) }
        if let detail = memo.detail { parts.append(detail) }
        return parts.joined(separator: ". ")
    }
}

/// The compose sheet behind **+ > Written memo**. Save keeps the text as a memo; a memo with no
/// text is discarded. Cancel keeps nothing.
struct WrittenMemoComposeSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                TextField("Write a memo. The first line becomes its title.", text: $text, axis: .vertical)
                    .font(.body)
                    .lineLimit(6...)
                    .focused($isFocused)
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .background(MemoPresentation.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Memo text")
                    .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Written memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }
}

/// The open memo: kind · time (· duration), the title, an action row with Memo → Task and Delete, and the text
/// editor. Edits save immediately. Closing a Written memo emptied of text discards it.
///
/// A Voice memo adds the cap note, its Transcript area (Transcribing…, or **Try again** with No
/// transcript, or the editable Transcript) and the audio player pinned to the bottom. Deleting
/// one confirms first.
struct MemoCardSheet: View {
    let memo: Memo
    let onEdit: (String) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    let loadAudio: () -> Data?
    let onRetryTranscription: () -> Void
    /// Starts **Memo → Task** for the memo's text, empty when it has none.
    let makeTaskSuggestions: (String) -> MemoTaskSuggestions

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isConfirmingDelete = false
    @State private var taskSuggestions: MemoTaskSuggestions?
    @FocusState private var isEditorFocused: Bool

    init(
        memo: Memo,
        onEdit: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void,
        loadAudio: @escaping () -> Data?,
        onRetryTranscription: @escaping () -> Void,
        makeTaskSuggestions: @escaping (String) -> MemoTaskSuggestions
    ) {
        self.memo = memo
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onClose = onClose
        self.loadAudio = loadAudio
        self.onRetryTranscription = onRetryTranscription
        self.makeTaskSuggestions = makeTaskSuggestions
        _text = State(initialValue: memo.text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let note = memo.capNote {
                    capNote(note)
                }
                actionRow
                if memo.kind == .voice {
                    transcriptArea
                } else {
                    editor
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if memo.kind == .voice {
                MemoAudioPlayerBar(loadAudio: loadAudio, duration: memo.duration)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onChange(of: text) { _, newText in onEdit(newText) }
        // A Transcript that arrives while the card is open replaces the empty one shown.
        .onChange(of: memo.transcriptState) { _, _ in
            if memo.kind == .voice { text = memo.text }
        }
        .confirmationDialog("Delete this voice memo?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("Its audio and transcript are removed. This can't be undone.")
        }
        .sheet(item: $taskSuggestions) { suggestions in
            MemoTaskSheet(suggestions: suggestions)
        }
        .onDisappear(perform: onClose)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: MemoPresentation.icon(for: memo.kind))
                    .accessibilityHidden(true)
                Text(headerLine)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -9)
                .padding(.trailing, -9)
                .accessibilityLabel("Close memo")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(KyoPalette.accent)
            .padding(.top, 14)

            let title = memo.kind == .voice ? memo.title : Memo.title(ofWrittenText: text)
            Text(title.isEmpty ? "Untitled" : title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(title.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// "Written memo · 9:41 AM", or "Voice memo · 9:41 AM · 0:42".
    private var headerLine: String {
        var parts = [MemoPresentation.kindName(for: memo.kind), MemoPresentation.time(memo.createdAt)]
        if memo.kind == .voice { parts.append(Memo.formattedDuration(memo.duration)) }
        return parts.joined(separator: " · ")
    }

    private func capNote(_ note: String) -> some View {
        Label(note, systemImage: "clock.badge.exclamationmark")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                taskSuggestions = makeTaskSuggestions(memo.taskSourceText(currentText: text))
            } label: {
                Label("Memo → Task", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KyoPalette.accent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(KyoPalette.accent.opacity(0.12), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Turns this memo into tasks on Today")

            Button(role: .destructive) {
                if memo.kind == .voice {
                    isConfirmingDelete = true
                } else {
                    onDelete()
                    dismiss()
                }
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete memo")
            .accessibilityHint("Deletes this memo permanently")
        }
    }

    private var editor: some View {
        TextField("Write something. The first line is the title.", text: $text, axis: .vertical)
            .font(.body)
            .lineLimit(6...)
            .focused($isEditorFocused)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(MemoPresentation.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Memo text")
    }

    @ViewBuilder
    private var transcriptArea: some View {
        switch memo.transcriptState ?? .noTranscript {
        case .transcribing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Transcribing…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .noTranscript:
            VStack(alignment: .leading, spacing: 12) {
                Text("No transcript")
                    .foregroundStyle(.secondary)
                Button(action: onRetryTranscription) {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KyoPalette.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(KyoPalette.accent.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Transcribes this recording again")
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        case .transcribed:
            TextField("Transcript", text: $text, axis: .vertical)
                .font(.body)
                .lineLimit(6...)
                .focused($isEditorFocused)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .background(MemoPresentation.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("Transcript")
        }
    }
}

/// Labels, icons and formatting shared by the memo views.
enum MemoPresentation {
    static func kindName(for kind: Memo.Kind) -> String {
        switch kind {
        case .written: "Written memo"
        case .voice: "Voice memo"
        }
    }

    static func icon(for kind: Memo.Kind) -> String {
        switch kind {
        case .written: "text.alignleft"
        case .voice: "waveform"
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static var cardBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1)
                : .white
        })
    }
}
