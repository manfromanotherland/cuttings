// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Session cache of parsed article bodies, so revisiting a reading shows
/// instantly — no re-parse, no spinner. Each entry keeps the body it was
/// parsed from, so the caller can cheaply detect an on-disk change (re-read
/// the body, string-compare) and re-parse only the reading that changed,
/// never throwing away the others' caches. LRU-evicted to fit `byteBudget`.
struct ArticleDocumentCache {
    typealias Entry = (body: String, document: ArticleDocument)

    /// Approximate memory ceiling for cached parses (LRU-evicted to fit). macOS
    /// has no hard per-app memory cap, so this is tidiness rather than a limit we
    /// must respect — ~32 MB holds hundreds of normal articles or a dozen-plus
    /// very large ones, far more than a session revisits.
    private let byteBudget = 32 * 1024 * 1024

    private var entries: [String: Entry] = [:]

    /// Eviction order, least-recently-used first.
    private var order: [String] = []

    /// The cached parse for `id`, marking it most-recently-used. `nil` when the
    /// reading hasn't been opened this session (or has been evicted).
    mutating func lookup(_ id: String) -> Entry? {
        guard let entry = entries[id] else { return nil }
        touch(id)
        return entry
    }

    /// Insert a parsed document (with the body it was parsed from), then evict
    /// the least-recently-used entries until the cache fits `byteBudget`.
    /// An article whose own estimated cost exceeds the whole budget is not cached
    /// at all — caching it would evict every other entry and still blow the
    /// ceiling. It still displays (it's the caller's current document); it just
    /// isn't retained once the user navigates away.
    mutating func store(body: String, document: ArticleDocument, for id: String) {
        let entry: Entry = (body: body, document: document)
        guard estimatedCost(entry) <= byteBudget else {
            // Too big to cache: drop any stale entry lingering under this id.
            remove(id)
            return
        }
        entries[id] = entry
        touch(id)
        var total = entries.values.reduce(0) { $0 + estimatedCost($1) }
        while total > byteBudget, order.count > 1 {
            let evicted = order.removeFirst()
            if let evictedEntry = entries.removeValue(forKey: evicted) {
                total -= estimatedCost(evictedEntry)
            }
        }
    }

    /// Drop `id`'s entry, if any (e.g. when its body grew past the parse limit
    /// and the cached parse would be stale).
    mutating func remove(_ id: String) {
        entries.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    /// Mark `id` as most-recently-used in the eviction order.
    private mutating func touch(_ id: String) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    /// Rough retained-memory estimate for one entry: the source bytes plus the
    /// swift-markdown tree, which runs ~3× the source — so ~4× overall. A coarse
    /// proxy (the real tree size isn't cheaply measurable), but enough to hold a
    /// predictable ceiling.
    private func estimatedCost(_ entry: Entry) -> Int {
        entry.body.utf8.count * 4
    }
}
