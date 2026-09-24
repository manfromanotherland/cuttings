// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One immutable board snapshot. Scope, search, and Spotlight ranking remain
/// coherent while the complete matching result is loaded.
private struct ReadingSnapshotContext {
    let generation: UInt64
    let scope: LibraryScope
    let search: String?
}

enum ReadingLoadResult: Equatable {
    case published
    case superseded
    case failed
}

// ── Reading list ─────────────────────────────────────────────────────────────
// Loading the list, debounced search, and tag metadata.

extension AppState {
    // ── Refresh (list + filters) ──────────────────────────────────────────

    func refresh() async {
        // Invalidate an older in-flight query before child tasks can yield; it
        // must not consume this content publication with pre-mutation rows.
        readingLoadGeneration &+= 1
        libraryContentRefreshPending = true
        await withTaskGroup(of: Void.self) { group in
            // A refresh follows a local mutation (or a watcher sync), so never
            // re-home a selection the mutation already advanced deliberately.
            group.addTask { _ = await self.loadReadings(resetSelectionIfMissing: false) }
            group.addTask { await self.loadFilters() }
        }
    }

    // ── List / search ─────────────────────────────────────────────────────

    /// Entry point for search-field edits. Debounces rapid typing so the core
    /// runs a single search once input settles (~150ms) instead of one pass per
    /// keystroke; each edit cancels the previous pending reload. Filter and
    /// refresh reloads call `loadReadings` directly and stay immediate.
    func searchDidChange() {
        searchTask?.cancel()
        invalidatePendingReadingLoads()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            // This reload fires ~150ms after the last keystroke, while the search
            // field is still focused. Preserve an unavailable focused card for
            // this reload so the state update cannot disturb the field editor and
            // let a global shortcut fire instead of editing the search term.
            _ = await loadReadings(
                resetSelectionIfMissing: !isEditingText,
                preferImmediateTextResults: true
            )
        }
    }

    /// The full-text query for the current search box, or nil when it's empty.
    private var activeQuery: String? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    /// Every reading in one immutable scope/search snapshot. LazyLayoutKit
    /// virtualizes card views, so the app never waits for a trailing page.
    private func fetchReadings(
        _ core: any CoreBridging,
        context: ReadingSnapshotContext,
        semanticCandidateIDs: [String]
    ) async throws -> [ReadingRow] {
        let query = ReadingQuery.boardSnapshot(
            scope: context.scope,
            search: context.search,
            semanticCandidateIDs: semanticCandidateIDs
        )
        return try await core.listReadings(query)
    }

    private func makeSnapshotContext() -> ReadingSnapshotContext {
        readingLoadGeneration &+= 1
        return ReadingSnapshotContext(
            generation: readingLoadGeneration,
            scope: activeScope,
            search: activeQuery
        )
    }

    private func loadSemanticCandidateIDs(for search: String?) async throws -> [String] {
        guard let search, let visualSearchCoordinator else { return [] }
        return try await visualSearchCoordinator.candidates(
            for: search,
            limit: semanticCandidateLimit
        )
    }

    private func isCurrent(_ context: ReadingSnapshotContext) -> Bool {
        context.generation == readingLoadGeneration
            && context.scope == activeScope
            && context.search == activeQuery
            && !Task.isCancelled
    }

    private func invalidatePendingReadingLoads() {
        readingLoadGeneration &+= 1
    }

    /// `resetSelectionIfMissing` controls what happens when the focused card is
    /// absent from the freshly loaded board. Direct reloads prune it; a
    /// `refresh()` after a local mutation may preserve an open reading that is
    /// deliberately outside the current filter (see `refresh()`).
    @discardableResult
    func loadReadings(
        resetSelectionIfMissing: Bool = true,
        includeSemanticSearch: Bool = true,
        preferImmediateTextResults: Bool = false
    ) async -> ReadingLoadResult {
        guard !Task.isCancelled else { return .superseded }
        guard let core else { return .failed }
        let context = makeSnapshotContext()
        let semanticCandidates: (@MainActor () async throws -> [String])?
        if includeSemanticSearch, context.search != nil, visualSearchCoordinator != nil {
            semanticCandidates = { try await self.loadSemanticCandidateIDs(for: context.search) }
        } else {
            semanticCandidates = nil
        }
        do {
            let completed = try await ReadingSnapshotDelivery.load(
                textFirst: preferImmediateTextResults,
                fetch: { candidates in
                    try await self.fetchReadings(core, context: context, semanticCandidateIDs: candidates)
                },
                semanticCandidates: semanticCandidates,
                isCurrent: { self.isCurrent(context) },
                publish: { rows, _ in self.publishReadings(rows) }
            )
            guard completed, isCurrent(context) else { return .superseded }

            // A text-only first result must not discard a selected semantic hit
            // that is still awaiting optional enrichment. Reconcile once the
            // captured query has finished, against its final published rows.
            if !boardSelection.selectedIDs.isEmpty || boardSelection.focusedID != nil {
                var selection = boardSelection
                selection.reconcile(
                    with: readings.map(\.id),
                    preserveUnavailableFocus: !resetSelectionIfMissing
                )
                if selection != boardSelection { boardSelection = selection }
            }
            return .published
        } catch {
            if isCurrent(context) {
                self.error = error.localizedDescription
                return .failed
            }
            return .superseded
        }
    }

    private func publishReadings(_ rows: [ReadingRow]) {
        // Reconciliation often confirms exactly the rows already displayed.
        // Keep their observation identity stable instead of invalidating the
        // board and detail hierarchy with an equal whole-array assignment.
        if readings != rows { readings = rows }
        // Body or same-path asset bytes can change while every row field stays
        // equal. Content invalidation remains independent of row publication.
        if libraryContentRefreshPending {
            libraryContentRefreshPending = false
            libraryContentGeneration &+= 1
        }
        TestHooks.recordStartupEvent("readings")
    }

    // ── Filter metadata ───────────────────────────────────────────────────

    func loadFilters() async {
        guard let core else { return }
        let session = librarySessionGeneration
        // The compatible FFI count payload still bundles legacy view/rating
        // counts. Only its global tag vocabulary is presentation state now.
        // Search and board facets must not rebuild/re-publish 13k tag values.
        guard let counts = try? await core.filterCounts(
            kind: nil, scope: .all, tag: nil, query: nil
        ) else { return }
        guard session == librarySessionGeneration else { return }
        let tags = counts.tags.map { TagCount($0) }
        if filters.tags != tags { filters.tags = tags }
    }

    /// Reload the board after its scope changes. The global tag vocabulary only
    /// changes when library files change.
    func reloadForFilterChange() async {
        _ = await loadReadings()
    }

    // ── Filter selection ──────────────────────────────────────────────────

    /// Switch to one exact board scope.
    func selectScope(_ scope: LibraryScope) {
        guard activeScope != scope else { return }
        activeScope = scope
        invalidatePendingReadingLoads()
        Task { await reloadForFilterChange() }
    }
}
