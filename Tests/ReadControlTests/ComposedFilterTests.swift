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
