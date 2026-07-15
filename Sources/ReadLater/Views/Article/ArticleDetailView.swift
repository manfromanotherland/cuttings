// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ArticleDetailView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("readerFont", store: AppDefaults.store) private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize", store: AppDefaults.store) private var readerFontSize: ReaderFontSize = .medium

    @State private var row: FfiReadingRow?
    @State private var articleDocument: ArticleDocument?
    @State private var isLoading = false
    /// True when the selected reading's body is too large to render (see
    /// `maxParseBytes`); drives the oversize notice instead of the reader.
    @State private var bodyTooLarge = false

    /// Parsed bodies of readings opened this session, so revisiting one shows
    /// instantly — no re-parse, no spinner (see `ArticleDocumentCache`).
    /// Highlights are deliberately not cached — they're an overlay reloaded on
    /// each open, so toggles made elsewhere still show on return.
    @State private var cache = ArticleDocumentCache()

    /// Drives the full-screen image-zoom overlay. Injected into the reader's
    /// environment so a clicked figure can raise the lightbox; observed here to
    /// present it over the whole detail pane (see `ImageLightbox`).
    @State private var imageZoom = ImageZoomPresenter()

    /// Bodies larger than this are not parsed at all — swift-markdown would
    /// freeze the main thread and spike memory on a pathological file. The
    /// reader shows an "open in browser" notice instead. ~10 MB is already
    /// ~1.5M words, far beyond any real article.
    private let maxParseBytes = 10 * 1024 * 1024
    /// Word-count companion to `maxParseBytes`: a reading this long is treated as
    /// too large *without* fetching its body (see `load`). No real article nears
    /// 1M words, so this short-circuits a pathological body before the reader reads
    /// and marshals megabytes across the FFI.
    private let maxParseWords: UInt32 = 1_000_000

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
        // Reader figures raise the full-screen zoom; the lightbox layers over the
        // whole detail pane (see `imageZoomOverlay`). Navigating away dismisses it.
        .imageZoomOverlay(imageZoom)
        // Load on appear too; `.onChange` alone misses the boot-time auto-selected reading.
        // Navigating away also closes any open lightbox so it can't linger.
        .onChange(of: appState.selectedId) { _, id in
            imageZoom.dismiss()
            Task { await load(id: id) }
        }
        .task { await load(id: appState.selectedId) }
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
                        if shouldApply { addTag(tag, to: row.id) } else { removeTag(tag, from: row.id) }
                    }
                )
            }
        }
    }

    // ── Article content ───────────────────────────────────────────────────

    private func articleView(row: FfiReadingRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            articleHeader(row: row)
            Divider()
            articleContent(row: row)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(row.title.isEmpty ? "Article" : row.title)
    }

    /// Fixed-height header above the reader's own scroll: title + metadata.
    private func articleHeader(row: FfiReadingRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(.largeTitle.bold())
                .accessibilityIdentifier(A11y.Detail.title)
            metadataRow(row: row)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private func metadataRow(row: FfiReadingRow) -> some View {
        HStack(spacing: 12) {
            if let site = row.site, !site.isEmpty {
                metadataLabel(site, systemImage: "globe")
            }
            if let author = row.author, !author.isEmpty {
                metadataLabel(author, systemImage: "person")
            }
            if let readingTime = row.readingTimeLabel {
                metadataLabel(readingTime, systemImage: "clock")
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
                    .accessibilityIdentifier(A11y.Detail.tags)
            }
        }
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.tightIcon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    /// The reader area below the header: the oversize notice, the parsed
    /// document, an excerpt-only fallback, or nothing.
    @ViewBuilder
    private func articleContent(row: FfiReadingRow) -> some View {
        // Native reader handles its own scrolling and fills remaining height
        if bodyTooLarge {
            OversizeNotice(url: row.url)
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
            excerptFallback(row: row, excerpt: excerpt)
                .id(row.id)
        } else {
            Spacer()
        }
    }

    /// Excerpt-only fallback when there's no parsed body to show.
    private func excerptFallback(row: FfiReadingRow, excerpt: String) -> some View {
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
    }

    // ── Rating control ────────────────────────────────────────────────────

    /// End-of-article rating (see `RatingFooter`). The optimistic wiring lives
    /// here because this view owns the detail `row` state: flip the stars now,
    /// then reconcile with the authoritative row once the core write + refresh
    /// land (falling back to the prior row if the write didn't take).
    private func ratingFooter(row: FfiReadingRow) -> some View {
        RatingFooter(row: row) { newValue in
            let previous = self.row
            var optimistic = row
            optimistic.rating = newValue
            self.row = optimistic
            Task {
                self.row = await appState.setRating(id: row.id, rating: newValue) ?? previous
            }
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableView("Select an article to read", systemImage: "doc.text")
            .accessibilityIdentifier(A11y.Detail.empty)
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
            ArticleToolbar(row: row, appState: appState)
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

        // Short-circuit a pathological body straight to the oversize notice from the
        // cheap indexed word count — before fetching (synchronously, on the main
        // thread) and parsing megabytes of text, the very cost this guard exists to
        // avoid. `present`'s exact byte check still backstops a missing word count.
        if let words = row?.wordCount, words > maxParseWords {
            articleDocument = nil
            bodyTooLarge = true
            isLoading = false
            return
        }

        // Revisiting an already-opened reading: show its parsed body straight
        // from the cache — no re-parse, no spinner — then revalidate just this
        // reading below. Highlights are reloaded so toggles made elsewhere show.
        if let cached = cache.lookup(id) {
            articleDocument = cached.document
            bodyTooLarge = false
            isLoading = false
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
            cache.remove(id)
            articleDocument = nil
            bodyTooLarge = true
            return
        }
        bodyTooLarge = false
        let document = ArticleDocument(markdown: body)
        cache.store(body: body, document: document, for: id)
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
