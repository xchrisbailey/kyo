import SwiftUI

/// The **Memo → Task** sheet: "Finding suggested tasks…", then up to 5 **Suggested tasks**, all
/// ticked and editable, with **Add to Today (n)**. With no suggestions it shows "No suggestions",
/// one blank task row and **Add another**. Added rows show "Added" and can't be added again while
/// the sheet is open.
struct MemoTaskSheet: View {
    @Environment(\.theme) private var theme
    @ObservedObject var suggestions: MemoTaskSuggestions

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedRow: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch suggestions.phase {
                        case .finding:
                            finding
                        case .suggestions:
                            rows
                        case .noSuggestions:
                            Text("No suggestions")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                            rows
                            addAnotherButton
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if suggestions.phase != .finding {
                    addToTodayButton
                }
            }
            .themedText()
            .background(theme.sheetBackground)
            .themedNavigationTitle("Memo → Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await suggestions.load() }
        .onChange(of: suggestions.phase) { _, phase in
            if phase == .noSuggestions { focusedRow = suggestions.rows.first?.id }
        }
        .onAppear {
            if suggestions.phase == .noSuggestions { focusedRow = suggestions.rows.first?.id }
        }
    }

    private var finding: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Finding suggested tasks…")
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                SuggestedTaskRow(
                    row: row,
                    focusedRow: $focusedRow,
                    onToggle: { suggestions.toggle(rowID: row.id) },
                    onEdit: { suggestions.edit(rowID: row.id, text: $0) }
                )
            }
        }
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addAnotherButton: some View {
        Button {
            focusedRow = suggestions.addAnother()
        } label: {
            Label("Add another", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(theme.accent.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var addToTodayButton: some View {
        let count = suggestions.addableCount
        return Button {
            focusedRow = nil
            suggestions.addToToday()
        } label: {
            Text("Add to Today (\(count))")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.onAccentText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(theme.accent.opacity(count == 0 ? 0.35 : 1), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// A Suggested task row: a tick, the editable text, and "Added" once it's on Today.
private struct SuggestedTaskRow: View {
    @Environment(\.theme) private var theme
    let row: MemoTaskSuggestions.Row
    var focusedRow: FocusState<UUID?>.Binding
    let onToggle: () -> Void
    let onEdit: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: row.isTicked || row.isAdded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(row.isTicked || row.isAdded ? theme.accent : theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(row.isAdded)
            .accessibilityLabel(row.isTicked ? "Included" : "Not included")
            .accessibilityHint("Toggles whether this task is added to Today")

            if row.isAdded {
                Text(row.text)
                    .font(.body)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Added")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
            } else {
                TextField(
                    "Task",
                    text: Binding(get: { row.text }, set: onEdit),
                    axis: .vertical
                )
                .font(.body)
                .focused(focusedRow, equals: row.id)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Task")
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 14)
        .frame(minHeight: 55)
    }
}
