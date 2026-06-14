// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ArticleDetailView: View {
    @EnvironmentObject private var appState: AppState

    @State private var row: FfiReadingRow?
    @State private var body: String?
    @State private var isLoading = false
    @State private var newTag = ""
    @State private var showTagInput = false

    var body: some View {
        Group {
            if let selectedId = appState.selectedId {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let row {
                    articleView(row: row)
                }
            } else {
                emptyDetail
            }
        }
        .onChange(of: appState.selectedId) { _, id in
            Task { await load(id: id) }
        }
        .toolbar { toolbarItems }
    }

    // ── Article content ───────────────────────────────────────────────────

    private func articleView(row: FfiReadingRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title.isEmpty ? "Untitled" : row.title)
                        .font(.largeTitle.bold())
                    HStack(spacing: 12) {
                        if let site = row.site, !site.isEmpty {
                            Label(site, systemImage: "globe")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let author = row.author, !author.isEmpty {
                            Label(author, systemImage: "person")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let wc = row.wordCount, wc > 0 {
                            Label("\(wc) words", systemImage: "text.alignleft")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    tagBar(row: row)
                }
                Divider()
                // Body
                if let body {
                    Text(body)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: 700, alignment: .leading)
                } else if let excerpt = row.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .padding(24)
        }
        .navigationTitle(row.title.isEmpty ? "Article" : row.title)
    }

    private func tagBar(row: FfiReadingRow) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(row.tags, id: \.self) { tag in
                tagChip(tag: tag, id: row.id)
            }
            if showTagInput {
                TextField("tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { commitTag(id: row.id) }
            } else {
                Button {
                    showTagInput = true
                } label: {
                    Label("Tag", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func tagChip(tag: String, id: String) -> some View {
        HStack(spacing: 2) {
            Text("#\(tag)")
                .font(.caption)
            Button {
                Task { await appState.removeTag(id: id, tag: tag) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.15), in: Capsule())
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select an article to read")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Toolbar ───────────────────────────────────────────────────────────

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if let row {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await appState.toggleRead(row) }
                } label: {
                    Label(
                        row.read ? "Mark Unread" : "Mark Read",
                        systemImage: row.read ? "circle" : "checkmark.circle"
                    )
                }
                .help(row.read ? "Mark as unread" : "Mark as read")

                Button {
                    Task { await appState.toggleFavorite(row) }
                } label: {
                    Label(
                        row.favorite ? "Unfavorite" : "Favorite",
                        systemImage: row.favorite ? "star.fill" : "star"
                    )
                }
                .help(row.favorite ? "Remove from favorites" : "Add to favorites")

                Button {
                    if let url = URL(string: row.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .help("Open original URL")
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private func load(id: String?) async {
        guard let id else { row = nil; body = nil; return }
        isLoading = true
        showTagInput = false
        newTag = ""
        row = appState.readings.first(where: { $0.id == id })
        body = await appState.getBody(id: id)
        isLoading = false
    }

    private func commitTag(id: String) {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        showTagInput = false
        newTag = ""
        guard !tag.isEmpty else { return }
        Task { await appState.addTag(id: id, tag: tag) }
    }
}

// ── FlowLayout ────────────────────────────────────────────────────────────────
// Simple wrapping HStack for tag chips.

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, in: proposal.replacingUnspecifiedDimensions()).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, in: bounds.size)
        for (view, origin) in zip(subviews, result.origins) {
            view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, in size: CGSize) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        var origins: [CGPoint] = []
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > size.width, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return (CGSize(width: size.width, height: y + rowH), origins)
    }
}
