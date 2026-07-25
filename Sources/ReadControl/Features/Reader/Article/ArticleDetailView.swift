// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ArticleDetailView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("readerFont", store: AppDefaults.store) private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize", store: AppDefaults.store) private var readerFontSize: ReaderFontSize = .medium

    @State private var row: ReadingRow?
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

    /// Drives the full-screen image-zoom overlay. Owned by `ContentView` (so the
    /// window toolbar can hide while it's up) and passed in here; injected into the
    /// reader's environment so a clicked figure can raise the lightbox, and
    /// observed to present it over the whole detail pane (see `ImageLightbox`).
    let imageZoom: ImageZoomPresenter

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

    /// Reader typography, derived once from the persisted font settings and shared
    /// by the body (`MarkdownDocumentView`) and the surrounding chrome
    /// (`ArticleHeaderView`, `RatingFooter`) so they all rescale together.
    private var theme: MarkdownTheme {
        MarkdownTheme(font: readerFont, fontSize: readerFontSize)
    }

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
        // The one trigger for loading: runs on appear *and* on every selection
        // change, and cancels a load still in flight when the selection moves on. A
        // `.task` plus a separate `.onChange` both fired for the same reading, so it
        // was fetched and parsed twice over. Navigating away also closes any open
        // lightbox so it can't linger.
        .task(id: appState.selectedId) {
            imageZoom.dismiss()
            await load(id: appState.selectedId)
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
                        if shouldApply {
                            addTag(tag, to: row.id)
                        } else {
                            removeTag(tag, from: row.id)
                        }
                    }
                )
            }
        }
    }

    // ── Article content ───────────────────────────────────────────────────

    private func articleView(row: ReadingRow) -> some View {
        articleContent(row: row)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(row.title.isEmpty ? "Article" : row.title)
    }

    /// The reader: the oversize notice, the parsed document, an excerpt-only
    /// fallback, or nothing. The article header is embedded inside the scroll
    /// area of each branch so it moves with the content.
    @ViewBuilder
    private func articleContent(row: ReadingRow) -> some View {
        if bodyTooLarge {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ArticleHeaderView(row: row, theme: theme)
                    OversizeNotice(url: row.url)
                }
            }
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
                header: { ArticleHeaderView(row: row, theme: theme) },
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
    private func excerptFallback(row: ReadingRow, excerpt: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArticleHeaderView(row: row, theme: theme)
                VStack(alignment: .leading, spacing: 0) {
                    Text(excerpt)
                        .foregroundStyle(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ratingFooter(row: row)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.bottom, 80)
            }
        }
    }

    // ── Rating control ────────────────────────────────────────────────────

    /// End-of-article rating (see `RatingFooter`). The optimistic wiring lives
    /// here because this view owns the detail `row` state: flip the stars now,
    /// then reconcile with the authoritative row once the core write + refresh
    /// land (falling back to the prior row if the write didn't take).
    private func ratingFooter(row: ReadingRow) -> some View {
        RatingFooter(row: row, theme: theme) { newValue in
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
    private var currentRow: ReadingRow? {
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
        // cheap indexed word count — before fetching and parsing megabytes of text,
        // the very cost this guard exists to avoid. `present`'s exact byte check
        // still backstops a missing word count.
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
            loadHighlightsInBackground(id: id)
            await revalidate(id: id, cachedBody: cached.body)
            return
        }

        isLoading = true
        loadHighlightsInBackground(id: id)
        // The native reader parses Markdown directly (linked images like
        // `[![alt](img)](url)` are handled by the renderer), so no HTML
        // conversion or asset-path rewriting is needed. Parse here, off the
        // per-render path, so re-rendering the reader never re-parses.
        let body = await appState.getBody(id: id)
        // A load can be superseded while the body is in flight: `.task(id:)` cancels
        // us, but neither the fetch above nor the detached parse in `present` observes
        // that cancellation. Bail before touching shared reader state so a stale load
        // can't paint over — or clear the spinner of — the reading now loading.
        guard appState.selectedId == id else { return }
        await present(body: body, id: id)
        guard appState.selectedId == id else { return }
        isLoading = false
    }

    /// Show a freshly fetched body: parse, cache, and display it — unless it
    /// exceeds `maxParseBytes`, in which case skip parsing entirely and flag it
    /// so the reader shows the oversize notice. The parse runs off the main
    /// thread (see `ArticleDocument.parse`), so a large article can't stall the
    /// UI. A nil body (nothing fetched) clears the reader.
    private func present(body: String?, id: String) async {
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
        let document = await ArticleDocument.parse(markdown: body)
        // Cache the finished parse under its own id even if the selection moved on
        // while it ran — the work is done and keyed by `id`, so revisiting hits the
        // cache instead of re-parsing.
        cache.store(body: body, document: document, for: id)
        // A detached parse can outlive the selection that asked for it — don't paint
        // it over the reading now on screen if the user moved on.
        guard appState.selectedId == id else { return }
        articleDocument = document
    }

    /// Fetch the reading's highlights *off* the reader's critical path.
    ///
    /// Highlights are a tint applied over already-rendered text, so nothing about
    /// showing the article depends on them — yet this was awaited *before* the body
    /// was even fetched, gating the whole reader on it. Firing it as a detached task
    /// lets the article render immediately; `appState.highlights` is observed, so the
    /// tint applies on the next render once it lands.
    private func loadHighlightsInBackground(id: String) {
        Task { await appState.loadHighlights(id: id) }
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
        await present(body: body, id: id)
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
