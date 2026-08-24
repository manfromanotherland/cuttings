// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The board's two durable scopes. Read, archive, and rating metadata remains in
/// the file format for compatibility but no longer participates in browsing.
enum LibraryScope: String, CaseIterable, Identifiable {
    case all, favorites
    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all: "All"
        case .favorites: "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .favorites: "heart"
        }
    }

    /// Whether `row` belongs in this library scope. `.all` deliberately includes
    /// cards carrying a legacy archived flag: archive remains readable metadata
    /// for format compatibility, but no longer changes presentation behavior.
    func contains(_ row: ReadingRow) -> Bool {
        switch self {
        case .all: true
        case .favorites: row.favorite
        }
    }
}
