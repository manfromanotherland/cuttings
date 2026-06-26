// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ArticleDetailView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("readerFont") private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize") private var readerFontSize: ReaderFontSize = .medium

    @State private var row: FfiReadingRow?
    @State private var articleMarkdown: String?
    @State private var isLoading = false
    @State private var newTag = ""
    @State private var showTagInput = false
    @State private var showHighlights = false
    @FocusState private var tagFieldFocused: Bool

    var body: some View {
        Group {
            if let selectedId = appState.selectedId {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let row {
                    articleView(row: row)
                } else if !isLoading {
                    // selectedId set but row not loaded yet — happens on first render
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyDetail
            }
        }
        .onChange(of: appState.selectedId) { _, id in
            Task { await load(id: id) }
        }
        .toolbar { toolbarItems }
        .inspector(isPresented: $showHighlights) {
            HighlightsInspector(readingId: appState.selectedId)
                .inspectorColumnWidth(min: 220, ideal: 280, max: 420)
        }
    }

    // ── Article content ───────────────────────────────────────────────────

    private func articleView(row: FfiReadingRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (fixed height, not scrolled by WKWebView)
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
                    if let readingTime = row.readingTimeLabel {
                        Label(readingTime, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .help(row.wordCount.map { "\($0) words" } ?? "")
                    }
                }
                tagBar(row: row)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Native reader handles its own scrolling and fills remaining height
            if let articleMarkdown {
                MarkdownDocumentView(
                    markdown: articleMarkdown,
                    libraryURL: appState.libraryURL,
                    font: readerFont,
                    fontSize: readerFontSize,
                    highlights: appState.highlights.map(\.text),
                    onHighlight: { text in
                        Task { await appState.toggleHighlight(id: row.id, text: text) }
                    },
                    footer: { ratingFooter(row: row) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let excerpt = row.excerpt, !excerpt.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(excerpt)
                            .foregroundStyle(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ratingFooter(row: row)
                    }
                    .padding(24)
                }
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(row.title.isEmpty ? "Article" : row.title)
    }


    // ── Rating control ────────────────────────────────────────────────────

    /// End-of-article rating: shown after the body so it surfaces when the
    /// reader reaches the end — rating is a judgment formed once you've read.
    private func ratingFooter(row: FfiReadingRow) -> some View {
        VStack(spacing: 12) {
            Divider()
            Text("Rate this article")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ratingControl(row: row)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private func ratingControl(row: FfiReadingRow) -> some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    // Clicking the current rating clears it back to unrated.
                    let target = UInt8(star)
                    let newValue: UInt8 = row.rating == target ? 0 : target
                    // Optimistic: flip the stars now, then reconcile with the
                    // authoritative row once the core write + refresh land
                    // (falling back to the prior row if the write didn't take).
                    let previous = self.row
                    var optimistic = row
                    optimistic.rating = newValue
                    self.row = optimistic
                    Task {
                        self.row = await appState.setRating(id: row.id, rating: newValue) ?? previous
                    }
                } label: {
                    Image(systemName: UInt8(star) <= row.rating ? "star.fill" : "star")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Rate \(star) star\(star == 1 ? "" : "s")")
            }
        }
        .font(.title3)
    }

    private func tagBar(row: FfiReadingRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(row.tags, id: \.self) { tag in
                    tagChip(tag: tag, id: row.id)
                }
                if showTagInput {
                    TextField("tag", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .focused($tagFieldFocused)
                        .onSubmit { commitTag(id: row.id) }
                        .onExitCommand { dismissTagInput() }
                } else {
                    Button {
                        showTagInput = true
                        tagFieldFocused = true
                    } label: {
                        Label("Tag", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Autocomplete suggestions drawn from existing tags in the library.
            if showTagInput {
                let suggestions = tagSuggestions(for: row)
                if !suggestions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                newTag = suggestion
                                commitTag(id: row.id)
                            } label: {
                                Text("#\(suggestion)")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    /// Existing library tags matching the current input, excluding tags already
    /// applied to this article. With an empty field, surfaces all available tags.
    private func tagSuggestions(for row: FfiReadingRow) -> [String] {
        let query = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        let applied = Set(row.tags.map { $0.lowercased() })
        return appState.allTags
            .map(\.tag)
            .filter { !applied.contains($0.lowercased()) }
            .filter { query.isEmpty || $0.lowercased().contains(query) }
            .prefix(8)
            .map { $0 }
    }

    private func tagChip(tag: String, id: String) -> some View {
        HStack(spacing: 2) {
            Text("#\(tag)")
                .font(.caption)
            Button {
                // Optimistic: drop the chip now, reconcile after the write.
                if var optimistic = row {
                    optimistic.tags.removeAll { $0 == tag }
                    row = optimistic
                }
                Task {
                    await appState.removeTag(id: id, tag: tag)
                    row = await appState.reloadRow(id: id) ?? row
                }
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

    /// The selected row resolved straight from the shared, synchronously
    /// published `appState.readings` (kept fresh by every mutation's refresh).
    /// Driving the toolbar from this — rather than the async-loaded `@State row`
    /// — makes the actions appear/disappear in the SAME render frame as the
    /// sort button (which also keys off `appState.readings`). Using the async
    /// `row` instead lets the two reflow a frame apart, which reads as a blink.
    private var currentRow: FfiReadingRow? {
        guard let id = appState.selectedId else { return nil }
        // Fall back to the loaded detail row when the selection sits outside the
        // current list — e.g. after re-rating the open article inside a rating
        // filter, where it stays selected and shown but drops off the list. Keeps
        // the toolbar populated instead of blanking the actions for what's on
        // screen.
        return appState.readings.first(where: { $0.id == id }) ?? (row?.id == id ? row : nil)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if let row = currentRow {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    // Drives off `currentRow` (optimistic), and on a selection
                    // advance `onChange(selectedId)` reloads the detail — so no
                    // `self.row` reload here, which would fight that advance.
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
                        systemImage: row.favorite ? "heart.fill" : "heart"
                    )
                }
                .help(row.favorite ? "Remove from favorites" : "Add to favorites")

                if row.archived {
                    Button {
                        Task { await appState.unarchive(row) }
                    } label: {
                        Label("Move to Library", systemImage: "tray.and.arrow.up")
                    }
                    .help("Move back to library")
                } else {
                    Button {
                        Task { await appState.archive(row) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .help("Archive this article")
                }

                Button {
                    if let url = URL(string: row.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .help("Open original URL")

                Button {
                    showHighlights.toggle()
                } label: {
                    Label("Highlights", systemImage: "highlighter")
                }
                .help("Show highlights")

                Button(role: .destructive) {
                    appState.pendingDelete = row
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Permanently delete this reading")
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private func load(id: String?) async {
        guard let id else {
            row = nil
            articleMarkdown = nil
            await appState.loadHighlights(id: nil)
            return
        }
        isLoading = true
        showTagInput = false
        newTag = ""
        row = appState.readings.first(where: { $0.id == id })
        await appState.loadHighlights(id: id)
        // The native reader parses Markdown directly (linked images like
        // `[![alt](img)](url)` are handled by the renderer), so no HTML
        // conversion or asset-path rewriting is needed.
        articleMarkdown = await appState.getBody(id: id)
        isLoading = false
    }

    private func commitTag(id: String) {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        newTag = ""
        guard !tag.isEmpty else { dismissTagInput(); return }
        // Optimistic: show the chip now (exact-match dedup + append mirror core).
        if var optimistic = row, !optimistic.tags.contains(tag) {
            optimistic.tags.append(tag)
            row = optimistic
        }
        Task {
            await appState.addTag(id: id, tag: tag)
            row = await appState.reloadRow(id: id) ?? row
        }
        // Keep the input open and focused so several tags can be added in a row.
        tagFieldFocused = true
    }

    private func dismissTagInput() {
        showTagInput = false
        tagFieldFocused = false
        newTag = ""
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
