// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// ── Mutations ────────────────────────────────────────────────────────────────
// Tag edits land optimistically, then the core write + `refresh()` reconcile.
// Deletion remains authoritative because it removes files from disk.

extension AppState {
    /// Optimistically apply an edit so it shows on the next frame, before the
    /// core write + `refresh()` land by swapping the row in the visible list (if
    /// present). Removing a row that no longer matches the filter is the explicit
    /// job of `advancePastFilteredRow`; re-ordering is left to the follow-up
    /// `refresh()`. A failed write self-heals from the index.
    private func applyOptimistic(_ old: ReadingRow, _ new: ReadingRow) {
        if let index = readings.firstIndex(where: { $0.id == old.id }) {
            readings[index] = new
        }
    }

    /// Mirror of the core's board scope: does `row` still belong in the list the
    /// user is currently looking at?
    private func rowMatchesCurrentFilter(_ row: ReadingRow) -> Bool {
        ComposedFilter.matches(row, scope: activeScope)
    }

    /// Pair with `applyOptimistic`: if the optimistic edit
    /// pushed the row out of the current filter, slide it out and advance the
    /// selection to an adjacent row in the *same* render tick — one motion, not
    /// an in-place icon flip followed a beat later by the row jumping away. A
    /// no-op when the row still matches. Skipped during search, whose FTS
    /// predicate is not mirrored in Swift.
    private func advancePastFilteredRow(id: String) {
        guard searchQuery.isEmpty,
              let index = readings.firstIndex(where: { $0.id == id }),
              !rowMatchesCurrentFilter(readings[index]) else { return }
        withAnimation {
            if selectedId == id {
                selectedId = ComposedFilter.selectionAfterRemoving(at: index, from: readings)
            }
            readings.remove(at: index)
        }
    }

    /// Permanently delete a reading: removes its file and assets from disk and
    /// its row from the index. Irreversible — callers should confirm first.
    func delete(_ row: ReadingRow) async {
        guard let core else { return }
        do {
            try await core.deleteReading(id: row.id)
            if selectedId == row.id {
                selectedId = nil
            }
            await refresh()
            scheduleVisualSearchReconciliation()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addTag(id: String, tag: String) async {
        guard let core else { return }
        // Mirror the core: trim, dedup on exact match, append (no sort/lowercase),
        // so the optimistic chip lands in the same place the reload confirms.
        let tag = tag.trimmingCharacters(in: .whitespaces)
        if let old = readings.first(where: { $0.id == id }), !old.tags.contains(tag) {
            var updated = old
            updated.tags.append(tag)
            applyOptimistic(old, updated)
        }
        try? await core.addTag(id: id, tag: tag)
        await refresh()
    }

    func removeTag(id: String, tag: String) async {
        guard let core else { return }
        if let old = readings.first(where: { $0.id == id }), old.tags.contains(tag) {
            var updated = old
            updated.tags.removeAll { $0 == tag }
            applyOptimistic(old, updated)
            advancePastFilteredRow(id: id)
        }
        try? await core.removeTag(id: id, tag: tag)
        await refresh()
    }

    func getBody(id: String) async -> String? {
        guard let core else { return nil }
        return try? await core.getBody(id: id)
    }

    /// Re-fetch a single reading row from the index (e.g. after a tag edit) so
    /// detail views can refresh their local copy without a full list reload.
    func reloadRow(id: String) async -> ReadingRow? {
        guard let core else { return nil }
        guard let fetched = try? await core.getReadingRow(id: id) else { return nil }
        return ReadingRow(fetched)
    }
}
