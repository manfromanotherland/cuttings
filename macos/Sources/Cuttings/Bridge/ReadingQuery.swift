// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A reading-list query in app language: the composed kind/scope/tag filter, an
/// optional full-text search, the sort, and paging. `CoreBridge` turns it into
/// the core's compatible `FfiListOptions` at the bridge boundary.
struct ReadingQuery {
    var kind: ReadingKind?
    var scope: LibraryScope
    var sort: ReadingSort
    var ascending: Bool
    var tag: String?
    var search: String?
    /// Core Spotlight's best-first semantic matches for `search`. The Rust
    /// core merges these candidates with its own text/label/colour results so
    /// filters, relevance ordering, and pagination stay one coherent query.
    var semanticCandidateIDs: [String]
    var limit: UInt32
    var offset: UInt32
}

extension ReadingQuery {
    /// The board always composes its selected scope and optional search into
    /// one core query. Search changes ordering, never the active kind scope.
    static func board(
        scope: LibraryScope,
        search: String?,
        semanticCandidateIDs: [String],
        limit: UInt32,
        offset: UInt32
    ) -> Self {
        Self(
            kind: nil,
            scope: scope,
            sort: search == nil ? .savedAt : .relevance,
            ascending: false,
            tag: nil,
            search: search,
            semanticCandidateIDs: semanticCandidateIDs,
            limit: limit,
            offset: offset
        )
    }
}
