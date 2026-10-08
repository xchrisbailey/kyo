import SwiftUI

/// The Memos sheet behind **See all**: a Today group, then **Memo history** grouped by day, newest
/// first, with a search field over titles, text and transcripts. Rows are Today's rows and open
/// the same card, so a past memo has the same actions. Memos load a page at a time as the
/// list is scrolled, and a row never loads photo or audio bytes.
struct MemosSheet: View {
    @ObservedObject var memoStore: MemoStore
    let languageModel: any OnDeviceLanguageModel
    @ObservedObject var taskList: TaskListStore

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var limit = MemoGroupsPage.pageSize
    @State private var page = MemoGroupsPage.empty
    @State private var openMemo: OpenMemo?
    @State private var voiceMemoPendingDelete: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Memos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search memos")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: reload)
        .onChange(of: query) { _, _ in
            limit = MemoGroupsPage.pageSize
            reload()
        }
        .onChange(of: limit) { _, _ in reload() }
        .onChange(of: memoStore.revision) { _, _ in reload() }
        .sheet(item: $openMemo) { open in
            if let memo = memoStore.memo(id: open.id) {
                MemoCardSheet(memo: memo, store: memoStore, languageModel: languageModel, taskList: taskList)
            }
        }
        .confirmationDialog(
            "Delete this voice memo?",
            isPresented: Binding(
                get: { voiceMemoPendingDelete != nil },
                set: { if !$0 { voiceMemoPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = voiceMemoPendingDelete { _ = memoStore.deleteMemo(id: id) }
                voiceMemoPendingDelete = nil
            }
        } message: {
            Text("Its audio and transcript are removed. This can't be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = page.noResultsMessage {
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if page.groups.isEmpty {
            Text("No memos yet")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(page.groups) { group in
                    section(group)
                }
                if page.hasMore {
                    // Scrolling to the end loads the next page.
                    Color.clear
                        .frame(height: 1)
                        .onAppear { limit += MemoGroupsPage.pageSize }
                        .id(limit)
                }
            }
        }
    }

    private func section(_ group: MemoDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title)
                .font(.title3.weight(.semibold))
                .tracking(-0.4)
                .frame(minHeight: 40, alignment: .bottom)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(group.results.enumerated()), id: \.element.id) { index, result in
                    if index > 0 {
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.55))
                            .frame(height: 0.5)
                            .accessibilityHidden(true)
                    }
                    MemoRow(
                        memo: result.memo,
                        loadThumbnail: { memoStore.thumbnailData(forPhotoID: $0) },
                        loadPhoto: { memoStore.photoData(forPhotoID: $0) },
                        onOpen: { openMemo = OpenMemo(id: result.memo.id) },
                        onDelete: { requestDelete(of: result.memo) },
                        highlight: page.query,
                        snippet: result.snippet
                    )
                }
            }
            .background(KyoPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private func reload() {
        page = memoStore.memoGroups(matching: query, limit: limit)
    }

    /// Voice memos confirm before they're deleted; Written memos go straight away.
    private func requestDelete(of memo: Memo) {
        if memo.kind == .voice {
            voiceMemoPendingDelete = memo.id
        } else {
            _ = memoStore.deleteMemo(id: memo.id)
        }
    }
}

private struct OpenMemo: Identifiable {
    let id: UUID
}
