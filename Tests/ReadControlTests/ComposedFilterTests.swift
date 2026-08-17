// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The pure composed-filter rules extracted from AppState: smart-view fallback,
/// single-select facet toggles, list membership, and post-removal selection —
/// the invariants the sidebar filtering and one-motion removal rely on. (The
/// async optimistic apply/reconcile around these stays covered by the UI
/// journeys.)
final class ComposedFilterTests: XCTestCase {
    /// Re-tapping the active view falls back to All; All itself stays; a different
    /// view switches. This is the "one active view, deselects to the base" rule.
    func testResolveViewFallsBackToAllOnReTap() {
        XCTAssertEqual(ComposedFilter.resolveView(active: .unread, tapped: .unread), .all)
        XCTAssertEqual(ComposedFilter.resolveView(active: .all, tapped: .all), .all)
        XCTAssertEqual(ComposedFilter.resolveView(active: .unread, tapped: .read), .read)
        XCTAssertEqual(ComposedFilter.resolveView(active: .favorites, tapped: .archive), .archive)
    }

    /// A single-select facet clears when its active value is re-tapped, and
    /// replaces otherwise — for both tags (String) and ratings (UInt8).
    func testToggleClearsOnReselectOtherwiseReplaces() {
        XCTAssertEqual(ComposedFilter.toggle(String?.none, "rust"), "rust")
        XCTAssertNil(ComposedFilter.toggle("rust", "rust"))
        XCTAssertEqual(ComposedFilter.toggle("rust", "swift"), "swift")
        XCTAssertEqual(ComposedFilter.toggle(UInt8?.none, 5), 5)
        XCTAssertNil(ComposedFilter.toggle(UInt8(5), 5))
        XCTAssertEqual(ComposedFilter.toggle(UInt8(5), 4), 4)
    }

    // ── Narrowing ───────────────────────────────────────────────────────────
    // Filters are ordered view → rating → tag, and changing one clears the
    // narrower ones below it.

    /// The worked example: Read ∩ ★5 ∩ #swift, then drop to ★4 — the tag goes.
    func testChangingTheRatingClearsTheTag() {
        let current = ComposedFilter.Selection(view: .read, rating: 5, tag: "swift")
        let next = ComposedFilter.togglingRating(4, from: current)
        XCTAssertEqual(next, ComposedFilter.Selection(view: .read, rating: 4, tag: nil))
    }

    /// …and switching Read → All drops both the rating and the tag.
    func testChangingTheViewClearsRatingAndTag() {
        let current = ComposedFilter.Selection(view: .read, rating: 5, tag: "swift")
        let next = ComposedFilter.selectingView(.all, from: current)
        XCTAssertEqual(next, ComposedFilter.Selection(view: .all, rating: nil, tag: nil))
    }

    /// Re-tapping the active view falls back to All — a change, so it cascades.
    func testFallingBackToAllAlsoClearsNarrowerFilters() {
        let current = ComposedFilter.Selection(view: .read, rating: 5, tag: "swift")
        let next = ComposedFilter.selectingView(.read, from: current)
        XCTAssertEqual(next, ComposedFilter.Selection(view: .all, rating: nil, tag: nil))
    }

    /// Broadening cascades as well: clearing a rating still clears the tag.
    func testClearingTheRatingClearsTheTag() {
        let current = ComposedFilter.Selection(view: .read, rating: 5, tag: "swift")
        let next = ComposedFilter.togglingRating(5, from: current)
        XCTAssertEqual(next, ComposedFilter.Selection(view: .read, rating: nil, tag: nil))
    }

    /// Tapping `.all` while it's already the base changes nothing, so it must not
    /// clear the filters below it.
    func testTappingAllWhileAlreadyTheBaseKeepsEverything() {
        let current = ComposedFilter.Selection(view: .all, rating: 5, tag: "swift")
        XCTAssertEqual(ComposedFilter.selectingView(.all, from: current), current)
    }

    /// The tag is the narrowest level: changing or clearing it touches nothing else.
    func testChangingTheTagLeavesViewAndRatingAlone() {
        let current = ComposedFilter.Selection(view: .read, rating: 5, tag: "swift")
        XCTAssertEqual(
            ComposedFilter.togglingTag("rust", from: current),
            ComposedFilter.Selection(view: .read, rating: 5, tag: "rust")
        )
        XCTAssertEqual(
            ComposedFilter.togglingTag("swift", from: current),
            ComposedFilter.Selection(view: .read, rating: 5, tag: nil)
        )
    }

    /// Selecting into an empty selection is unaffected by the cascade.
    func testSelectingFromAnEmptySelectionJustApplies() {
        let base = ComposedFilter.Selection(view: .all, rating: nil, tag: nil)
        XCTAssertEqual(
            ComposedFilter.selectingView(.unread, from: base),
            ComposedFilter.Selection(view: .unread, rating: nil, tag: nil)
        )
        XCTAssertEqual(
            ComposedFilter.togglingRating(4, from: base),
            ComposedFilter.Selection(view: .all, rating: 4, tag: nil)
        )
    }

    /// Membership is the intersection of view, tag, and rating.
    func testMatchesIntersectsViewTagAndRating() {
        var row = makeReadingRow(read: false, archived: false)
        row.tags = ["rust"]
        row.rating = 4
        XCTAssertTrue(ComposedFilter.matches(row, view: .all, tag: nil, rating: nil))
        XCTAssertTrue(ComposedFilter.matches(row, view: .all, tag: "rust", rating: 4))
        XCTAssertFalse(ComposedFilter.matches(row, view: .all, tag: "swift", rating: nil))
        XCTAssertFalse(ComposedFilter.matches(row, view: .all, tag: nil, rating: 3))
    }

    /// A row excluded by the smart view fails regardless of tag/rating.
    func testMatchesRejectsRowOutsideTheView() {
        var archived = makeReadingRow(archived: true)
        archived.tags = ["rust"]
        XCTAssertFalse(ComposedFilter.matches(archived, view: .all, tag: "rust", rating: nil))
        XCTAssertTrue(ComposedFilter.matches(archived, view: .archive, tag: "rust", rating: nil))
    }

    /// One-motion removal: advance to the next row, else the previous, else clear.
    func testSelectionAfterRemovingPrefersNextThenPreviousThenNil() {
        let rows = [rowWithId("a"), rowWithId("b"), rowWithId("c")]
        XCTAssertEqual(ComposedFilter.selectionAfterRemoving(at: 0, from: rows), "b")
        XCTAssertEqual(ComposedFilter.selectionAfterRemoving(at: 2, from: rows), "b")
        XCTAssertNil(ComposedFilter.selectionAfterRemoving(at: 0, from: [rowWithId("only")]))
    }

    private func rowWithId(_ id: String) -> ReadingRow {
        var row = makeReadingRow()
        row.id = id
        return row
    }
}
