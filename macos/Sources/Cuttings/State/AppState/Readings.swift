// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One immutable board snapshot. Scope, search, and Spotlight ranking remain
/// coherent while the complete matching result is loaded.
private struct ReadingSnapshotContext {
    let generation: UInt64
    let scope: LibraryScope
    let search: String?
    let semanticCandidateIDs: [String]
}

// ── Reading list ─────────────────────────────────────────────────────────────
// Loading the list, debounced search, and tag metadata.

extension AppState {
    // ── Refresh (list + filters) ──────────────────────────────────────────

    func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            // A refresh follows a local mutation (or a watcher sync), so never
            // re-home a selection the mutation already advanced deliberately.
            group.addTask { await self.loadReadings(resetSelectionIfMissing: false) }
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
            await loadReadings(resetSelectionIfMissing: !isEditingText)
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
        context: ReadingSnapshotContext
    ) async throws -> [ReadingRow] {
        let query = ReadingQuery.boardSnapshot(
            scope: context.scope,
            search: context.search,
            semanticCandidateIDs: context.semanticCandidateIDs
        )
        return try await core.listReadings(query).map { ReadingRow($0) }
    }

    private func makeSnapshotContext() async -> ReadingSnapshotContext? {
        readingLoadGeneration &+= 1
        let generation = readingLoadGeneration
        let scope = activeScope
        let search = activeQuery

        let semanticCandidateIDs: [String]
        do {
            semanticCandidateIDs = try await loadSemanticCandidateIDs(for: search)
        } catch is CancellationError {
            // A newer Spotlight generation or reading load superseded this
            // snapshot. Do not mistake cancellation for zero semantic hits.
            return nil
        } catch {
            // Core Spotlight is an optional enhancement. A genuine query
            // failure still leaves Rust text/label/colour search available.
            semanticCandidateIDs = []
        }

        guard generation == readingLoadGeneration,
              scope == activeScope,
              search == activeQuery,
              !Task.isCancelled else { return nil }
        return ReadingSnapshotContext(
            generation: generation,
            scope: scope,
            search: search,
            semanticCandidateIDs: semanticCandidateIDs
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
    func loadReadings(resetSelectionIfMissing: Bool = true) async {
        guard let core else { return }
        guard let context = await makeSnapshotContext() else { return }
        do {
            let rows = try await fetchReadings(core, context: context)
            guard isCurrent(context) else { return }
            readings = rows

            boardSelection.reconcile(
                with: rows.map(\.id),
                preserveUnavailableFocus: !resetSelectionIfMissing
            )
        } catch {
            if isCurrent(context) {
                self.error = error.localizedDescription
            }
        }
    }

    // ── Filter metadata ───────────────────────────────────────────────────

    func loadFilters() async {
        guard let core else { return }
        // The compatible FFI count payload still bundles legacy view/rating
        // counts. Only its global tag vocabulary is presentation state now.
        // Search and board facets must not rebuild/re-publish 13k tag values.
        guard let counts = try? await core.filterCounts(
            kind: nil, scope: .all, tag: nil, query: nil
        ) else { return }
        filters.tags = counts.tags.map { TagCount($0) }
    }

    /// Reload the board after its scope changes. The global tag vocabulary only
    /// changes when library files change.
    func reloadForFilterChange() async {
        await loadReadings()
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
