// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ArticleDetailView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("readerFont") private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize") private var readerFontSize: ReaderFontSize = .medium

    @State private var row: FfiReadingRow?
    @State private var articleDocument: ArticleDocument?
    @State private var isLoading = false
    /// True when the selected reading's body is too large to render (see
    /// `maxParseBytes`); drives the oversize notice instead of the reader.
    @State private var bodyTooLarge = false

    /// Parsed bodies of readings opened this session, so revisiting one shows
    /// instantly — no re-parse, no spinner. Each entry keeps the body it was
    /// parsed from; on revisit the cached parse is shown at once and that single
    /// reading is revalidated in the background (re-read its body, re-parse only
    /// if it changed on disk). So an external edit to one file refreshes just
    /// that reading and never throws away the others' caches. LRU-evicted to fit
    /// `cacheByteBudget`. Highlights are deliberately not cached — they're an
    /// overlay reloaded on each open, so toggles made elsewhere still show on
    /// return.
    @State private var documentCache: [String: (body: String, document: ArticleDocument)] = [:]
    @State private var cacheOrder: [String] = []

    /// Approximate memory ceiling for cached parses (LRU-evicted to fit). macOS
    /// has no hard per-app memory cap, so this is tidiness rather than a limit we
    /// must respect — ~32 MB holds hundreds of normal articles or a dozen-plus
    /// very large ones, far more than a session revisits.
    private let cacheByteBudget = 32 * 1024 * 1024

    /// Bodies larger than this are not parsed at all — swift-markdown would
    /// freeze the main thread and spike memory on a pathological file. The
    /// reader shows an "open in browser" notice instead. ~10 MB is already
    /// ~1.5M words, far beyond any real article.
    private let maxParseBytes = 10 * 1024 * 1024

    var body: some View {
        @Bindable var appState = appState
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
        .inspector(isPresented: $appState.showHighlights) {
            HighlightsInspector(readingId: appState.selectedId)
                .inspectorColumnWidth(min: 220, ideal: 280, max: 420)
        }
        .sheet(isPresented: $appState.showTagSheet) {
            if let row {
                // Driven by the detail `row`, which add/removeTag update
                // synchronously — so checkmarks flip the instant you toggle.
                TagPickerSheet(
                    applied: row.tags,
                    allTags: appState.sidebar.tags.map(\.tag),
                    onToggle: { tag, shouldApply in
                        if shouldApply { addTag(tag, to: row.id) }
                        else { removeTag(tag, from: row.id) }
                    }
                )
            }
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
                            .labelStyle(.tightIcon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let author = row.author, !author.isEmpty {
                        Label(author, systemImage: "person")
                            .labelStyle(.tightIcon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let readingTime = row.readingTimeLabel {
                        Label(readingTime, systemImage: "clock")
                            .labelStyle(.tightIcon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .help(row.wordCount.map { "\($0) words" } ?? "")
                    }
                    if !row.tags.isEmpty {
                        Spacer()
                        // Plain read-only label pushed to the trailing edge; adding
                        // / removing tags happens in the tag sheet (the # toolbar
                        // button).
                        Text(row.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Native reader handles its own scrolling and fills remaining height
            if bodyTooLarge {
                oversizeNotice(row: row)
            } else if let articleDocument {
                MarkdownDocumentView(
                    document: articleDocument,
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
                // Identity tied to the reading so switching articles builds a
                // fresh ScrollView (scrolled to top) instead of inheriting the
                // previous article's offset. Keyed on `row.id` — not the parsed
                // document — so background revalidation of the *same* reading
                // (which can swap in a re-parsed document) doesn't reset scroll.
                .id(row.id)
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
                .id(row.id)
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
                .accessibilityLabel("Rate \(star) star\(star == 1 ? "" : "s")")
            }
        }
        .font(.title3)
    }

    private var emptyDetail: some View {
        ContentUnavailableView("Select an article to read", systemImage: "doc.text")
    }

    /// Shown instead of the reader when a reading's body is too large to parse
    /// (see `maxParseBytes`). The full text is still available in the browser.
    private func oversizeNotice(row: FfiReadingRow) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("This article is too large to display in the reader")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Open it in your browser to read the full text.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if let url = URL(string: row.url) {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
                    appState.showTagSheet = true
                } label: {
                    Label("Tags", systemImage: "number")
                }
                .help("Edit tags")

                Button {
                    appState.showHighlights.toggle()
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
            articleDocument = nil
            bodyTooLarge = false
            await appState.loadHighlights(id: nil)
            return
        }
        row = appState.readings.first(where: { $0.id == id })

        // Revisiting an already-opened reading: show its parsed body straight
        // from the cache — no re-parse, no spinner — then revalidate just this
        // reading below. Highlights are reloaded so toggles made elsewhere show.
        if let cached = documentCache[id] {
            articleDocument = cached.document
            bodyTooLarge = false
            isLoading = false
            touch(id)
            await appState.loadHighlights(id: id)
            await revalidate(id: id, cachedBody: cached.body)
            return
        }

        isLoading = true
        await appState.loadHighlights(id: id)
        // The native reader parses Markdown directly (linked images like
        // `[![alt](img)](url)` are handled by the renderer), so no HTML
        // conversion or asset-path rewriting is needed. Parse here, off the
        // per-render path, so re-rendering the reader never re-parses.
        let body = await appState.getBody(id: id)
        present(body: body, id: id)
        isLoading = false
    }

    /// Show a freshly fetched body: parse, cache, and display it — unless it
    /// exceeds `maxParseBytes`, in which case skip parsing entirely (it would
    /// freeze the main thread) and flag it so the reader shows the oversize
    /// notice. A nil body (nothing fetched) clears the reader.
    private func present(body: String?, id: String) {
        guard let body else {
            articleDocument = nil
            bodyTooLarge = false
            return
        }
        guard body.utf8.count <= maxParseBytes else {
            // Too large to render: don't parse, and don't keep any stale cache.
            documentCache.removeValue(forKey: id)
            cacheOrder.removeAll { $0 == id }
            articleDocument = nil
            bodyTooLarge = true
            return
        }
        bodyTooLarge = false
        let document = ArticleDocument(markdown: body)
        store(body: body, document: document, id: id)
        articleDocument = document
    }

    /// After showing a reading from cache, re-read its body and re-parse only if
    /// it changed on disk — so an external edit to a single file refreshes just
    /// that reading, leaving every other cached reading intact. Cheap when
    /// nothing changed (a body fetch + string compare), and off the critical
    /// path since the cached parse is already on screen.
    private func revalidate(id: String, cachedBody: String) async {
        let body = await appState.getBody(id: id)
        // Bail if the user moved on, or nothing changed.
        guard appState.selectedId == id, let body, body != cachedBody else { return }
        present(body: body, id: id)
    }

    /// Insert a parsed document (with the body it was parsed from), then evict
    /// the least-recently-used entries until the cache fits `cacheByteBudget`.
    /// An article whose own estimated cost exceeds the whole budget is not cached
    /// at all — caching it would evict every other entry and still blow the
    /// ceiling. It still displays (it's the current `articleDocument`); it just
    /// isn't retained once you navigate away.
    private func store(body: String, document: ArticleDocument, id: String) {
        let entry = (body: body, document: document)
        guard estimatedCost(entry) <= cacheByteBudget else {
            // Too big to cache: drop any stale entry lingering under this id.
            documentCache.removeValue(forKey: id)
            cacheOrder.removeAll { $0 == id }
            return
        }
        documentCache[id] = entry
        touch(id)
        var total = documentCache.values.reduce(0) { $0 + estimatedCost($1) }
        while total > cacheByteBudget, cacheOrder.count > 1 {
            let evicted = cacheOrder.removeFirst()
            if let evictedEntry = documentCache.removeValue(forKey: evicted) {
                total -= estimatedCost(evictedEntry)
            }
        }
    }

    /// Rough retained-memory estimate for one entry: the source bytes plus the
    /// swift-markdown tree, which runs ~3× the source — so ~4× overall. A coarse
    /// proxy (the real tree size isn't cheaply measurable), but enough to hold a
    /// predictable ceiling.
    private func estimatedCost(_ entry: (body: String, document: ArticleDocument)) -> Int {
        entry.body.utf8.count * 4
    }

    /// Mark `id` as most-recently-used in the eviction order.
    private func touch(_ id: String) {
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
    }

    /// Apply a tag to the article: optimistically show the chip now (exact-match
    /// dedup + append mirror the core), then write through and reconcile.
    private func addTag(_ tag: String, to id: String) {
        let tag = tag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        if var optimistic = row, !optimistic.tags.contains(tag) {
            optimistic.tags.append(tag)
            row = optimistic
        }
        Task {
            await appState.addTag(id: id, tag: tag)
            row = await appState.reloadRow(id: id) ?? row
        }
    }

    /// Remove a tag from the article: optimistically drop the chip, reconcile
    /// after the write.
    private func removeTag(_ tag: String, from id: String) {
        if var optimistic = row {
            optimistic.tags.removeAll { $0 == tag }
            row = optimistic
        }
        Task {
            await appState.removeTag(id: id, tag: tag)
            row = await appState.reloadRow(id: id) ?? row
        }
    }
}
