// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A reading-list query in app language: the composed view/tag/rating filter, an
/// optional full-text search, the sort, and paging. `CoreBridge` turns it into the
/// core's `FfiListOptions`, keeping that boundary DTO inside the bridge (ADR 0001).
struct ReadingQuery {
    var view: SidebarItem
    var sort: ReadingSort
    var ascending: Bool
    var tag: String?
    var rating: UInt8?
    var search: String?
    var limit: UInt32
    var offset: UInt32
}
