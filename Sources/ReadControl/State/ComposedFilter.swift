// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Pure decision logic for the composed filter — the active smart view, tag, and
/// rating applied together as an intersection over the reading list (mirrors the
/// core's `list.rs`). Extracted from `AppState` so it can be unit-tested without
/// the core, filesystem, or AppKit; `AppState` holds the state and delegates the
/// rules here. The async optimistic apply/reconcile stays in `AppState`.
enum ComposedFilter {
    /// The active smart view after `tapped` is clicked. Clicking the
    /// already-active view falls back to `.all` — except `.all` itself, which is
    /// the base and stays — mirroring how a tag/rating toggles off, since the view
    /// always has a value and so deselects to the base rather than to nothing.
    static func resolveView(active: SidebarItem, tapped: SidebarItem) -> SidebarItem {
        (tapped == active && tapped != .all) ? .all : tapped
    }

    /// A single-select facet (tag or rating) after `tapped` is clicked: selecting
    /// the active value clears it, otherwise it becomes the selection. This is why
    /// at most one tag and one rating can be active at a time.
    static func toggle<Value: Equatable>(_ selected: Value?, _ tapped: Value) -> Value? {
        selected == tapped ? nil : tapped
    }

    /// Whether `row` belongs in the list under the composed filter: it must be in
    /// the smart view and match the selected tag and rating (each optional).
    static func matches(_ row: ReadingRow, view: SidebarItem, tag: String?, rating: UInt8?) -> Bool {
        guard view.contains(row) else { return false }
        if let tag, !row.tags.contains(tag) {
            return false
        }
        if let rating, row.rating != rating {
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
