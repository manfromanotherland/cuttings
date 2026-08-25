// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One immutable first-page search snapshot. Later pages reuse its complete
/// Spotlight candidate ranking instead of running a fresh semantic query at a
/// different offset.
struct ReadingPageContext {
    let generation: UInt64
    let scope: LibraryScope
    let search: String?
    let semanticCandidateIDs: [String]
}

// ── Reading list ─────────────────────────────────────────────────────────────
// Loading and paginating the list, debounced search, and tag metadata.

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
            // field is still focused. Re-homing the list selection here moves
            // first responder to the list, flips `isEditingText` false, and lets
            // a global shortcut fire instead of editing the search term. Leave
            // selection put while the field is active.
            await loadReadings(resetSelectionIfMissing: !isEditingText)
        }
    }

    /// The full-text query for the current search box, or nil when it's empty.
    private var activeQuery: String? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    /// One page of readings for an immutable scope/search snapshot at `offset`.
    private func fetchReadings(
        _ core: any CoreBridging,
        context: ReadingPageContext,
        offset: UInt32
    ) async throws -> [ReadingRow] {
        let query = ReadingQuery.board(
            scope: context.scope,
            search: context.search,
            semanticCandidateIDs: context.semanticCandidateIDs,
            limit: pageSize,
            offset: offset
        )
        return try await core.listReadings(query).map { ReadingRow($0) }
    }

    private func makePageContext() async -> ReadingPageContext? {
        readingLoadGeneration &+= 1
        isLoadingMore = false
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
        return ReadingPageContext(
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

    private func isCurrent(_ context: ReadingPageContext) -> Bool {
        context.generation == readingLoadGeneration
            && context.scope == activeScope
            && context.search == activeQuery
            && !Task.isCancelled
    }

    private func invalidatePendingReadingLoads() {
        readingLoadGeneration &+= 1
        readingPageContext = nil
        isLoadingMore = false
    }

    /// `resetSelectionIfMissing` controls what happens when the current
    /// selection isn't in the freshly loaded list. Direct (re)loads — filter
    /// switch, search, first load — pass `true` to re-home onto the first
    /// row. A `refresh()` after a local mutation passes `false` to leave the
    /// selection alone (see `refresh()`). An empty selection always defaults to
    /// the first row either way.
    func loadReadings(resetSelectionIfMissing: Bool = true) async {
        guard let core else { return }
        guard let context = await makePageContext() else { return }
        do {
            let rows = try await fetchReadings(core, context: context, offset: 0)
            guard isCurrent(context) else { return }
            readings = rows
            hasMoreReadings = rows.count == Int(pageSize)
            readingPageContext = context

            // Open the first reading by default so selection-dependent UI is
            // available without an extra click. A missing selection is re-homed
            // to the first item only when the caller asked (direct reloads); a
            // post-mutation refresh leaves a
            // deliberately off-list selection — the open reading — in place.
            if selectedId == nil
                || (resetSelectionIfMissing && !readings.contains(where: { $0.id == selectedId }))
            {
                selectedId = readings.first?.id
            }
        } catch {
            if isCurrent(context) {
                self.error = error.localizedDescription
            }
        }
    }

    func loadMoreReadings() async {
        guard hasMoreReadings,
              !isLoadingMore,
              let core,
              let context = readingPageContext,
              isCurrent(context) else { return }
        isLoadingMore = true
        let offset = readings.count
        defer {
            if context.generation == readingLoadGeneration {
                isLoadingMore = false
            }
        }
        do {
            let rows = try await fetchReadings(core, context: context, offset: UInt32(offset))
            guard isCurrent(context), readings.count == offset else { return }
            let existingIDs = Set(readings.map(\.id))
            readings.append(contentsOf: rows.filter { !existingIDs.contains($0.id) })
            hasMoreReadings = rows.count == Int(pageSize)
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
