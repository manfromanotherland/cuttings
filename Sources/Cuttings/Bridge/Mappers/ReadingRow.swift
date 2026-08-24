// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The kind of thing saved in the library. Files store a stable lowercase value;
/// the FFI exposes the same vocabulary as an exhaustive enum. The core maps a
/// legacy file with no kind to `.article` before it reaches this boundary.
enum ReadingKind: String, CaseIterable, Sendable {
    case article
    case image
    case quote
    case video

    init(_ kind: FfiReadingKind) {
        switch kind {
        case .article: self = .article
        case .image: self = .image
        case .quote: self = .quote
        case .video: self = .video
        }
    }

    var ffiKind: FfiReadingKind {
        switch self {
        case .article: .article
        case .image: .image
        case .quote: .quote
        case .video: .video
        }
    }
}

/// A list/search/sidebar presentation snapshot of a reading, kept apart from the
/// `FfiReadingRow` boundary DTO so feature code speaks app language rather than
/// "this came from the Rust FFI" (see ADR 0001). It mirrors the boundary fields
/// exactly and as `var`, so the optimistic-UI edits in `AppState.Mutations`
/// (`var updated = row; updated.read.toggle()`) copy-and-tweak a row unchanged.
/// It is a snapshot, never persisted truth — mutations go through the core.
struct ReadingRow: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var url: String
    var canonicalUrl: String
    var author: String?
    var site: String?
    var savedAt: String
    var read: Bool
    var archived: Bool
    var favorite: Bool
    var rating: UInt8
    var excerpt: String?
    var wordCount: UInt32?
    var lang: String?
    var tags: [String]
    var kind: ReadingKind = .article
    var mediaUrl: String?
    var previewAsset: String?
}

extension ReadingRow {
    /// Maps the FFI boundary row into a presentation snapshot. Field-for-field
    /// today; the seam for any future presentation-only derivations (e.g. parsing
    /// `savedAt` into a `Date`) so views never see the boundary type.
    init(_ row: FfiReadingRow) {
        id = row.id
        title = row.title
        url = row.url
        canonicalUrl = row.canonicalUrl
        author = row.author
        site = row.site
        savedAt = row.savedAt
        read = row.read
        archived = row.archived
        favorite = row.favorite
        rating = row.rating
        excerpt = row.excerpt
        wordCount = row.wordCount
        lang = row.lang
        tags = row.tags
        kind = ReadingKind(row.kind)
        mediaUrl = row.mediaUrl
        previewAsset = row.previewAsset
    }
}
