// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Sidebar items ──────────────────────────────────────────────────────────────
// The smart views are one of three independent, composable sidebar filters (view
// + tag + rating); see `AppState.activeView` / `selectedTag` / `selectedRating`.

enum SidebarItem: String, CaseIterable, Identifiable {
    case all, unread, read, archive, favorites
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .read: "Read"
        case .archive: "Archive"
        case .favorites: "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .unread: "circle"
        case .read: "checkmark.circle"
        case .archive: "archivebox"
        case .favorites: "heart"
        }
    }

    var ffiView: FfiView {
        switch self {
        case .all: .all
        case .unread: .unread
        case .read: .read
        case .archive: .archive
        case .favorites: .favorites
        }
    }

    /// Whether `row` belongs in this smart view — the single Swift mirror of the
    /// core's view clauses (see `list.rs`). Used both to filter rows against the
    /// current view and to fold optimistic edits into the sidebar view counts,
    /// so the two can never drift apart.
    func contains(_ row: ReadingRow) -> Bool {
        switch self {
        case .all:       !row.archived
        case .unread:    !row.archived && !row.read
        case .read:      !row.archived && row.read
        case .archive:   row.archived
        case .favorites: row.favorite
        }
    }
}
