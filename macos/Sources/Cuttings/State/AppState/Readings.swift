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
            await loadReadings(resetSelectionIfMissing: !isEditingText)
            // The sidebar badges are faceted by the search, so a query change has
            // to recount them alongside the list.
            await loadSidebar()
        }
    }

    /// The full-text query for the current search box, or nil when it's empty.
    private var activeQuery: String? {
        searchQuery.isEmpty ? nil : searchQuery
    }

    /// The sort to apply: Relevance while searching, the persisted field
    /// otherwise (search is just another filter through the same list path).
    private var activeSort: ReadingSort {
        activeQuery == nil ? sortField : searchSort
    }

    /// One page of readings for the current view/filter/sort/search at `offset`,
    /// as presentation rows. The view, tag, and rating compose with the search as
    /// an intersection; the bridge turns these Swift values into the core's query
    /// (see `CoreBridge.listReadings`).
    private func fetchReadings(_ core: any CoreBridging, offset: UInt32) async throws -> [ReadingRow] {
        let query = ReadingQuery(
            kind: selectedKind, view: activeView, sort: activeSort, ascending: sortAscending,
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
            kind: selectedKind, view: activeView, tag: selectedTag,
            rating: selectedRating, query: activeQuery
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
    // The three sidebar filters — smart view, rating, tag — compose as an
    // intersection (with the search box), but they are *ordered*: view, then
    // rating, then tag, top to bottom as the sidebar reads. Changing one clears
    // the narrower ones below it, so the list always answers the question the
    // last click asked. Clicking an active tag or rating toggles it off; the view
    // always has a value (`.all` is the unfiltered base), so it falls back to
    // that base rather than to nothing. The rules live in `ComposedFilter`.

    /// Select a saved-item kind, or clear the kind facet with `nil`. Unlike the
    /// ordered view/rating/tag stack this is a peer facet, so it does not discard
    /// any of those selections.
    func selectKind(_ kind: ReadingKind?) {
        guard selectedKind != kind else { return }
        selectedKind = kind
        Task { await reloadForSelectionChange() }
    }

    /// Switch the active smart view — or fall back to `.all` when the
    /// already-active view is clicked again — and clear the rating and tag
    /// beneath it. Clicking `.all` while it's already the base changes nothing,
    /// and so clears nothing.
    func selectView(_ item: SidebarItem) {
        apply(ComposedFilter.selectingView(item, from: filterSelection))
    }

    /// Select a rating filter, or clear it if the same rating is already active.
    /// Either way the rating changed, so the tag beneath it is cleared.
    func toggleRating(_ rating: UInt8) {
        apply(ComposedFilter.togglingRating(rating, from: filterSelection))
    }

    /// Select a tag filter, or clear it if the same tag is already active. The
    /// narrowest filter, so it leaves the view and rating alone.
    func toggleTag(_ tag: String) {
        apply(ComposedFilter.togglingTag(tag, from: filterSelection))
    }

    /// The three sidebar filters as one value, for `ComposedFilter` to resolve.
    private var filterSelection: ComposedFilter.Selection {
        .init(view: activeView, rating: selectedRating, tag: selectedTag)
    }

    /// Adopt a resolved selection and reload, doing nothing when it matches what
    /// is already applied. Each property is assigned only when it actually
    /// differs: every one of them persists to defaults in `didSet`, so blind
    /// assignment would rewrite unchanged keys and churn observation.
    private func apply(_ selection: ComposedFilter.Selection) {
        guard selection != filterSelection else { return }
        if activeView != selection.view {
            activeView = selection.view
        }
        if selectedRating != selection.rating {
            selectedRating = selection.rating
        }
        if selectedTag != selection.tag {
            selectedTag = selection.tag
        }
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
