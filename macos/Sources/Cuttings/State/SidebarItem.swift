// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The durable scopes exposed by the board toolbar. Read, archive, and rating
/// metadata remains in the file format for compatibility but no longer
/// participates in browsing.
enum LibraryScope: String, CaseIterable, Identifiable {
    case all, favorites, media, articles, notes, links, quotes

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all: "All"
        case .favorites: "Favourites"
        case .media: "Media"
        case .articles: "Articles"
        case .notes: "Notes"
        case .links: "Links"
        case .quotes: "Quotes"
        }
    }

    var icon: String {
        switch self {
        case .all: "asterisk"
        case .favorites: "heart"
        case .media: "photo.on.rectangle"
        case .articles: "newspaper"
        case .notes: "heart.text.square"
        case .links: "link"
        case .quotes: "quote.opening"
        }
    }

    /// Whether `row` belongs in this library scope. `.all` deliberately includes
    /// cards carrying a legacy archived flag: archive remains readable metadata
    /// for format compatibility, but no longer changes presentation behavior.
    func contains(_ row: ReadingRow) -> Bool {
        switch self {
        case .all: true
        case .favorites: row.favorite
        case .media: row.kind == .image || row.kind == .video
        case .articles: row.kind == .article && !row.lightweight
        case .notes: row.hasNote
        case .links: row.kind == .article && row.lightweight
        case .quotes: row.kind == .quote
        }
    }
}
