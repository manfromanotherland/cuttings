// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Pure decision logic for the board's library scope and optional tag filter.
/// Extracted from `AppState` so it can be unit-tested without the core,
/// filesystem, or AppKit.
enum ComposedFilter {
    /// The active scope after `tapped` is clicked. Clicking Favorites again falls
    /// back to All; All itself is the stable base.
    static func resolveScope(active: LibraryScope, tapped: LibraryScope) -> LibraryScope {
        (tapped == active && tapped != .all) ? .all : tapped
    }

    /// A single-select facet after `tapped` is clicked: selecting the active value
    /// clears it, otherwise it becomes the selection.
    static func toggle<Value: Equatable>(_ selected: Value?, _ tapped: Value) -> Value? {
        selected == tapped ? nil : tapped
    }

    // ── Narrowing ───────────────────────────────────────────────────────────

    /// The board's two filter selections as one value.
    struct Selection: Equatable {
        var scope: LibraryScope
        var tag: String?
    }

    /// Apply a scope click. A scope change clears the narrower tag filter; a
    /// no-op click on All leaves the current selection untouched.
    static func selectingScope(_ tapped: LibraryScope, from current: Selection) -> Selection {
        let scope = resolveScope(active: current.scope, tapped: tapped)
        guard scope != current.scope else { return current }
        return Selection(scope: scope, tag: nil)
    }

    /// Apply a tag click without changing the current library scope.
    static func togglingTag(_ tapped: String, from current: Selection) -> Selection {
        Selection(scope: current.scope, tag: toggle(current.tag, tapped))
    }

    /// Whether `row` belongs in the list under the selected scope and tag.
    static func matches(_ row: ReadingRow, scope: LibraryScope, tag: String?) -> Bool {
        guard scope.contains(row) else { return false }
        if let tag, !row.tags.contains(tag) {
            return false
        }
        return true
    }

    /// The selection to land on when the row at `index` leaves the list (it fell
    /// out of the filter): the next row, else the previous, else nothing. Computed
    /// against the list *before* the removal.
    static func selectionAfterRemoving(at index: Int, from readings: [ReadingRow]) -> String? {
        if index + 1 < readings.count {
            return readings[index + 1].id
        }
        if index > 0 {
            return readings[index - 1].id
        }
        return nil
    }
}
