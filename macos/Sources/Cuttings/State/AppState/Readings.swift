// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

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
        searchQuery.isEmpty ? nil : searchQuery
    }

    /// The board's fixed ordering: relevance while searching, newest saved first
    /// otherwise (search is just another filter through the same list path).
    private var activeSort: ReadingSort {
        activeQuery == nil ? .savedAt : .relevance
    }

    /// One page of readings for the current scope/filter/sort/search at `offset`.
    private func fetchReadings(_ core: any CoreBridging, offset: UInt32) async throws -> [ReadingRow] {
        let query = ReadingQuery(
            kind: nil, scope: activeScope, sort: activeSort, ascending: false,
            tag: nil, search: activeQuery,
            limit: pageSize, offset: offset
        )
        return try await core.listReadings(query).map { ReadingRow($0) }
    }

    /// `resetSelectionIfMissing` controls what happens when the current
    /// selection isn't in the freshly loaded list. Direct (re)loads — filter
    /// switch, search, first load — pass `true` to re-home onto the first
    /// row. A `refresh()` after a local mutation passes `false` to leave the
    /// selection alone (see `refresh()`). An empty selection always defaults to
    /// the first row either way.
    func loadReadings(resetSelectionIfMissing: Bool = true) async {
        guard let core else { return }
        do {
            let rows = try await fetchReadings(core, offset: 0)
            readings = rows
            hasMoreReadings = rows.count == Int(pageSize)

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
            self.error = error.localizedDescription
        }
    }

    func loadMoreReadings() async {
        guard hasMoreReadings, !isLoadingMore, let core else { return }
        isLoadingMore = true
        do {
            let rows = try await fetchReadings(core, offset: UInt32(readings.count))
            readings.append(contentsOf: rows)
            hasMoreReadings = rows.count == Int(pageSize)
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingMore = false
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
        Task { await reloadForFilterChange() }
    }
}
