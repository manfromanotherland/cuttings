// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Presentation snapshots of the sidebar's count sections, kept apart from the
// `FfiTagCount` / `FfiRatingCount` / `FfiViewCounts` boundary DTOs so feature
// code and the `SidebarCounts` state speak app language, not "this came from the
// Rust FFI" (see ADR 0001). Each mirrors its boundary DTO's fields exactly.

/// One library tag with its usage count under the active search/facet scope.
struct TagCount: Identifiable, Equatable, Sendable {
    var tag: String
    var count: UInt64
    var id: String {
        tag
    }
}

/// One star bucket (1–5) with how many readings hold it under the active scope.
struct RatingCount: Identifiable, Equatable, Sendable {
    var rating: UInt8
    var count: UInt64
    var id: UInt8 {
        rating
    }
}

/// The five smart-view totals returned by one sidebar recount.
struct ViewCounts: Equatable, Sendable {
    var all: UInt64
    var unread: UInt64
    var read: UInt64
    var archive: UInt64
    var favorites: UInt64
}

extension TagCount {
    init(_ ffi: FfiTagCount) {
        tag = ffi.tag
        count = ffi.count
    }
}

extension RatingCount {
    init(_ ffi: FfiRatingCount) {
        rating = ffi.rating
        count = ffi.count
    }
}

extension ViewCounts {
    init(_ ffi: FfiViewCounts) {
        all = ffi.all
        unread = ffi.unread
        read = ffi.read
        archive = ffi.archive
        favorites = ffi.favorites
    }
}
