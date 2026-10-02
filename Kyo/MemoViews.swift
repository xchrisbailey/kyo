import SwiftUI
import UIKit

/// A row in Today's Memos section: the kind icon, the title, a detail excerpt and the creation
/// time on the right. Tapping opens the memo; swiping or long-pressing deletes it.
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
                    if let detail = memo.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(MemoPresentation.time(memo.createdAt))
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

    /// Kind, title and time, then the detail excerpt when there is one.
    private var accessibilityLabel: String {
        var parts = [MemoPresentation.kindName(for: memo.kind), memo.title, MemoPresentation.time(memo.createdAt)]
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

/// The open memo: kind · time, the title, an action row with Delete, and the text editor.
/// Edits save immediately. Closing a memo emptied of text discards it.
struct MemoCardSheet: View {
    let memo: Memo
    let onEdit: (String) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isEditorFocused: Bool

    init(memo: Memo, onEdit: @escaping (String) -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.memo = memo
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onClose = onClose
        _text = State(initialValue: memo.text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actionRow
                editor
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onChange(of: text) { _, newText in onEdit(newText) }
        .onDisappear(perform: onClose)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: MemoPresentation.icon(for: memo.kind))
                    .accessibilityHidden(true)
                Text("\(MemoPresentation.kindName(for: memo.kind)) · \(MemoPresentation.time(memo.createdAt))")
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

            let title = Memo.title(ofWrittenText: text)
            Text(title.isEmpty ? "Untitled" : title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(title.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                onDelete()
                dismiss()
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
