// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The sidebar's badge numbers — smart-view counts, tag counts, and rating
/// counts — plus the optimistic bookkeeping that keeps them current between
/// the core's authoritative recounts (`AppState.loadSidebar()`).
struct SidebarCounts {
    var viewCounts: [SidebarItem: Int] = [:]

    /// All library tags with usage counts, most-used first (`list_tags` order).
    var tags: [FfiTagCount] = []

    /// Star buckets in use, highest first (`list_ratings` order).
    var ratings: [FfiRatingCount] = []

    /// Authoritative recount: adopt the core's grouped view counts, replacing
    /// any optimistic drift.
    mutating func setViewCounts(_ counts: FfiViewCounts) {
        viewCounts = [
            .all: Int(counts.all),
            .unread: Int(counts.unread),
            .read: Int(counts.read),
            .archive: Int(counts.archive),
            .favorites: Int(counts.favorites)
        ]
    }

    /// Fold a row's before/after state into the counts, mirroring the core's
    /// count rules so the optimistic numbers match what `loadSidebar()`
    /// reconciles to: view counts follow the `list.rs` clauses via
    /// `SidebarItem.contains` (Favorites counts regardless of archived); tag
    /// and rating counts include only non-archived readings (`tags.rs` /
    /// `rating.rs`).
    mutating func applyDelta(from old: FfiReadingRow, to new: FfiReadingRow) {
        for item in SidebarItem.allCases {
            let delta = (item.contains(new) ? 1 : 0) - (item.contains(old) ? 1 : 0)
            if delta != 0 { viewCounts[item] = max(0, (viewCounts[item] ?? 0) + delta) }
        }

        func tagContributes(_ row: FfiReadingRow, _ tag: String) -> Bool {
            !row.archived && row.tags.contains(tag)
        }
        for tag in Set(old.tags).union(new.tags) {
            let delta = (tagContributes(new, tag) ? 1 : 0) - (tagContributes(old, tag) ? 1 : 0)
            if delta != 0 { bumpTag(tag, by: delta) }
        }

        func ratingBucket(_ row: FfiReadingRow) -> UInt8? {
            (!row.archived && (1...5).contains(row.rating)) ? row.rating : nil
        }
        let oldBucket = ratingBucket(old), newBucket = ratingBucket(new)
        if oldBucket != newBucket {
            if let oldBucket { bumpRating(oldBucket, by: -1) }
            if let newBucket { bumpRating(newBucket, by: 1) }
        }
    }

    /// Adjust a tag's count, dropping it at zero and inserting it when it first
    /// appears, then re-sort to match `list_tags` (count desc, then name asc).
    private mutating func bumpTag(_ tag: String, by delta: Int) {
        if let index = tags.firstIndex(where: { $0.tag == tag }) {
            let count = Int(tags[index].count) + delta
            if count <= 0 { tags.remove(at: index) } else { tags[index].count = UInt64(count) }
        } else if delta > 0 {
            tags.append(FfiTagCount(tag: tag, count: UInt64(delta)))
        }
        tags.sort { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// Adjust a star bucket's count, dropping it at zero and inserting it when
    /// it first appears, keeping `list_ratings`' highest-first order.
    private mutating func bumpRating(_ rating: UInt8, by delta: Int) {
        if let index = ratings.firstIndex(where: { $0.rating == rating }) {
            let count = Int(ratings[index].count) + delta
            if count <= 0 { ratings.remove(at: index) } else { ratings[index].count = UInt64(count) }
        } else if delta > 0 {
            ratings.append(FfiRatingCount(rating: rating, count: UInt64(delta)))
        }
        ratings.sort { $0.rating > $1.rating }
    }
}
