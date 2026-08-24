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
    var limit: UInt32
    var offset: UInt32
}
