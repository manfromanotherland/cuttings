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

    // ── Narrowing ───────────────────────────────────────────────────────────

    /// The sidebar's three filter selections as one value.
    struct Selection: Equatable {
        var view: SidebarItem
        var rating: UInt8?
        var tag: String?
    }

    // The three filters are **hierarchical, not independent**, in the order the
    // sidebar reads top to bottom: the smart view is the broadest, a rating
    // narrows it, and a tag narrows that again. Changing a filter therefore
    // clears every narrower one below it.
    //
    // The alternative — leaving them in place — strands the reader on a
    // combination they never asked for: going from ★5 to ★4 while `#swift` is
    // still applied silently answers a different question than the one the click
    // asked, and most often lands on an empty list whose cause is off-screen in a
    // collapsed section. Broadening cascades too: dropping a rating, or falling
    // back from Read to All, is still a change at that level.
    //
    // Selecting a tag clears nothing — it is already the narrowest level.

    /// Apply a smart-view click. Clears the rating and tag, unless the click
    /// didn't change the view (tapping `.all` while it's already the base), which
    /// leaves the whole selection untouched.
    static func selectingView(_ tapped: SidebarItem, from current: Selection) -> Selection {
        let view = resolveView(active: current.view, tapped: tapped)
        guard view != current.view else { return current }
        return Selection(view: view, rating: nil, tag: nil)
    }

    /// Apply a rating click, clearing the tag. Every rating click changes the
    /// rating — to the tapped value, or to nothing when it was already active —
    /// so this always cascades.
    static func togglingRating(_ tapped: UInt8, from current: Selection) -> Selection {
        Selection(view: current.view, rating: toggle(current.rating, tapped), tag: nil)
    }

    /// Apply a tag click. The narrowest level, so nothing below it to clear.
    static func togglingTag(_ tapped: String, from current: Selection) -> Selection {
        Selection(view: current.view, rating: current.rating, tag: toggle(current.tag, tapped))
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
