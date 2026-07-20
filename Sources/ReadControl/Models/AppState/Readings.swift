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
        }
    }

    /// List options for the current view/filter/sort/search state at `offset`.
    /// Search is just another filter: a full-text query flows through the same
    /// list path (composing with the active view), ranked by the chosen sort —
    /// Relevance while searching, the persisted field otherwise.
    private func makeListOptions(offset: UInt32) -> FfiListOptions {
        let query = searchQuery.isEmpty ? nil : searchQuery
        return FfiListOptions(
            view: activeView.ffiView,
            sort: (query == nil ? sortField : searchSort).ffi,
            ascending: sortAscending,
            tag: selectedTag,
            rating: selectedRating,
            since: nil, until: nil,
            query: query,
            limit: pageSize, offset: offset
        )
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
            let result = try await core.listReadings(opts: makeListOptions(offset: 0))
            readings = result
            hasMoreReadings = result.count == Int(pageSize)

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
            let opts = makeListOptions(offset: UInt32(readings.count))
            let result = try await core.listReadings(opts: opts)
            readings.append(contentsOf: result)
            hasMoreReadings = result.count == Int(pageSize)
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingMore = false
    }

    // ── Sidebar counts & tags ─────────────────────────────────────────────

    func loadSidebar() async {
        guard let core else { return }
        do {
            // One grouped COUNT query for all five badges, instead of
            // materializing up to 9,999 full rows per view. This is only the
            // authoritative recount — the optimistic `SidebarCounts.applyDelta`
            // path still updates the badges within a frame and reconciles here.
            sidebar.setViewCounts(try await core.viewCounts())
            sidebar.tags = try await core.listTags()
            sidebar.ratings = try await core.listRatings()
        } catch {
            // Sidebar counts are non-critical; don't surface as an error.
        }
    }

    // ── Tag navigation ────────────────────────────────────────────────────

    func selectTag(_ tag: String) async {
        sidebarSelection = .tag(tag)
        await loadReadings()
    }

    func clearTag() async {
        sidebarSelection = .view(.all)
        await loadReadings()
    }
}
