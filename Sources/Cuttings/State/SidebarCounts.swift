// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The sidebar's badge numbers — smart-view counts, tag counts, and rating
/// counts — plus the optimistic bookkeeping that keeps them current between
/// the core's authoritative recounts (`AppState.loadSidebar()`).
struct SidebarCounts {
    var viewCounts: [SidebarItem: Int] = [:]

    /// All library tags with usage counts, alphabetical (`list_tags` order).
    var tags: [TagCount] = []

    /// Star buckets in use, highest first (`list_ratings` order).
    var ratings: [RatingCount] = []

    /// Authoritative recount: adopt the core's grouped view counts, replacing
    /// any optimistic drift.
    mutating func setViewCounts(_ counts: ViewCounts) {
        viewCounts = [
            .all: Int(counts.all),
            .unread: Int(counts.unread),
            .read: Int(counts.read),
            .archive: Int(counts.archive),
            .favorites: Int(counts.favorites)
        ]
    }

    /// Fold a row's before/after state into the smart-view counts, mirroring the
    /// core's *faceted* rule (`list.rs` `count_where`) so the optimistic numbers
    /// match what `loadSidebar()` reconciles to: a view count is gated by the
    /// selected `kind`/`tag`/`rating` (the other sections), never by the view itself.
    ///
    /// Only the view badges are updated optimistically. The Tags and Ratings
    /// sections show a *pinned presence set* (which tiles exist, scoped by the
    /// search/view) that a single-row delta can't reconstruct, so they refresh
    /// from the authoritative `loadSidebar()` recount that follows every mutation.
    ///
    /// The caller passes the current selection and must skip this while a search
    /// is active — the FTS query can't be evaluated in Swift, so searching relies
    /// on the recount instead.
    mutating func applyDelta(
        from old: ReadingRow, to new: ReadingRow,
        kind selectedKind: ReadingKind? = nil,
        tag selectedTag: String?, rating selectedRating: UInt8?
    ) {
        func matchesCross(_ row: ReadingRow) -> Bool {
            if let selectedKind, row.kind != selectedKind {
                return false
            }
            if let selectedTag, !row.tags.contains(selectedTag) {
                return false
            }
            if let selectedRating, row.rating != selectedRating {
                return false
            }
            return true
        }
        for item in SidebarItem.allCases {
            func inView(_ row: ReadingRow) -> Bool {
                matchesCross(row) && item.contains(row)
            }
            let delta = (inView(new) ? 1 : 0) - (inView(old) ? 1 : 0)
            if delta != 0 {
                viewCounts[item] = max(0, (viewCounts[item] ?? 0) + delta)
            }
        }
    }
}
