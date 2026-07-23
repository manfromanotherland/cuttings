// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Reading list ─────────────────────────────────────────────────────────────
// Loading and paginating the list, debounced search, and the sidebar reloads
// that keep the badges in step with it.

extension AppState {
    // ── Refresh (list + sidebar) ──────────────────────────────────────────

    func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            // A refresh follows a local mutation (or a watcher sync): never
            // re-home the selection here. The mutation already set the selection
            // it wants — advancing to a neighbour, or deliberately staying on a
            // row it just filtered out (e.g. re-rating the open article while in
            // a rating filter). Stealing it would desync the list highlight from
            // the open reading and strand the phantom-selected next row.
            group.addTask { await self.loadReadings(resetSelectionIfMissing: false) }
            group.addTask { await self.loadSidebar() }
        }
    }

    // ── List / search ─────────────────────────────────────────────────────

    /// Entry point for search-field edits. Debounces rapid typing so the core
    /// runs a single search once input settles (~150ms) instead of one pass per
    /// keystroke; each edit cancels the previous pending reload. Non-search
    /// reloads (filter, sort, refresh) call `loadReadings` directly and stay
    /// immediate.
    func searchDidChange() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            // This reload fires ~150ms after the last keystroke, while the search
            // field is still focused. Re-homing the list selection here moves
            // first responder to the list, flips `isEditingText` false, and lets
            // ⌘⌫ (Archive) fire instead of deleting to the start of the search
            // term. So while a text field is being edited, leave the selection
            // put to keep focus in the field; re-home only when not editing.
            await self.loadReadings(resetSelectionIfMissing: !self.isEditingText)
            // The sidebar badges are faceted by the search, so a query change has
            // to recount them alongside the list.
            await self.loadSidebar()
        }
    }

    /// The full-text query for the current search box, or nil when it's empty.
    private var activeQuery: String? { searchQuery.isEmpty ? nil : searchQuery }

    /// The sort to apply: Relevance while searching, the persisted field
    /// otherwise (search is just another filter through the same list path).
    private var activeSort: ReadingSort { activeQuery == nil ? sortField : searchSort }

    /// One page of readings for the current view/filter/sort/search at `offset`,
    /// as presentation rows. The view, tag, and rating compose with the search as
    /// an intersection; the bridge turns these Swift values into the core's query
    /// (see `CoreBridge.listReadings`).
    private func fetchReadings(_ core: any CoreBridging, offset: UInt32) async throws -> [ReadingRow] {
        let query = ReadingQuery(
            view: activeView, sort: activeSort, ascending: sortAscending,
            tag: selectedTag, rating: selectedRating, search: activeQuery,
            limit: pageSize, offset: offset
        )
        return try await core.listReadings(query).map { ReadingRow($0) }
    }

    /// `resetSelectionIfMissing` controls what happens when the current
    /// selection isn't in the freshly loaded list. Direct (re)loads — filter
    /// switch, sort, search, first load — pass `true` to re-home onto the first
    /// row. A `refresh()` after a local mutation passes `false` to leave the
    /// selection alone (see `refresh()`). An empty selection always defaults to
    /// the first row either way.
    func loadReadings(resetSelectionIfMissing: Bool = true) async {
        guard let core else { return }
        do {
            let rows = try await fetchReadings(core, offset: 0)
            readings = rows
            hasMoreReadings = rows.count == Int(pageSize)

            // Open the first reading by default so selection-dependent UI (the
            // reader and its toolbar, including Sort) is visible without an extra
            // click. A missing selection is re-homed to the first item only when
            // the caller asked (direct reloads); a post-mutation refresh leaves a
            // deliberately off-list selection — the open reading — in place.
            if selectedId == nil
                || (resetSelectionIfMissing && !readings.contains(where: { $0.id == selectedId })) {
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

    // ── Sidebar counts & tags ─────────────────────────────────────────────

    func loadSidebar() async {
        guard let core else { return }
        // One batched recount for all three sidebar sections, scoped to the active
        // search + selected facets (faceted navigation: each section refines
        // against the *other* sections' selections). The core resolves the
        // full-text match once and returns the view/tag/rating counts together in
        // a single pass.
        //
        // This is the authoritative recount: the Tags/Ratings tiles come solely
        // from here, while the optimistic `SidebarCounts.applyDelta` path updates
        // the view badges within a frame (when not searching) and reconciles here.
        // Sidebar counts are non-critical, so a failed fetch just leaves the
        // sections as-is rather than surfacing an error.
        guard let counts = try? await core.sidebarCounts(
            view: activeView, tag: selectedTag, rating: selectedRating, query: activeQuery
        ) else { return }
        sidebar.setViewCounts(ViewCounts(counts.views))
        sidebar.tags = counts.tags.map { TagCount($0) }
        sidebar.ratings = counts.ratings.map { RatingCount($0) }
    }

    /// Reload after a sidebar selection change (a new smart view, tag, or
    /// rating): the list for the new selection, plus the faceted sidebar counts,
    /// which now depend on the selection because selecting a facet refines the
    /// other sections. Runs both concurrently, like `refresh()`.
    func reloadForSelectionChange() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadReadings() }
            group.addTask { await self.loadSidebar() }
        }
    }

    // ── Sidebar filter selection ──────────────────────────────────────────
    // The three sidebar filters — smart view, tag, rating — are independent and
    // compose (with the search box). Selecting one leaves the others in place;
    // clicking an active tag or rating toggles it off. The view always has a value
    // (`.all` is the unfiltered base), so it switches rather than toggling off.

    /// Switch the active smart view, or fall back to `.all` when the already-active
    /// view is clicked again — mirroring how a tag/rating toggles off, except the
    /// view always has a value so it deselects to the `.all` base rather than to
    /// nothing. Clicking `.all` while it's active is a no-op (it's already the base).
    func selectView(_ item: SidebarItem) {
        let newView = ComposedFilter.resolveView(active: activeView, tapped: item)
        guard newView != activeView else { return }
        activeView = newView
        Task { await reloadForSelectionChange() }
    }

    /// Select a rating filter, or clear it if the same rating is already active.
    func toggleRating(_ rating: UInt8) {
        selectedRating = ComposedFilter.toggle(selectedRating, rating)
        Task { await reloadForSelectionChange() }
    }

    /// Select a tag filter, or clear it if the same tag is already active.
    func toggleTag(_ tag: String) {
        selectedTag = ComposedFilter.toggle(selectedTag, tag)
        Task { await reloadForSelectionChange() }
    }

    /// Clear the tag filter (the reading list's "Clear tag filter" empty-state
    /// action); leaves the view, rating, and search in place.
    func clearTag() async {
        guard selectedTag != nil else { return }
        selectedTag = nil
        await reloadForSelectionChange()
    }
}
