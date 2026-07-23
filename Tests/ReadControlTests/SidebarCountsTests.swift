// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `SidebarCounts` owns the sidebar's view badges: `setViewCounts` adopts the
/// core's authoritative recount, and `applyDelta` folds one optimistic row edit
/// into those badges between recounts, faceted by the active tag/rating. These
/// tests pin both against the core's rules (`list.rs`).
final class SidebarCountsTests: XCTestCase {

    func testSetViewCountsAdoptsAllFiveViews() {
        var counts = SidebarCounts()
        counts.setViewCounts(ViewCounts(all: 10, unread: 4, read: 6, archive: 3, favorites: 2))
        XCTAssertEqual(counts.viewCounts[.all], 10)
        XCTAssertEqual(counts.viewCounts[.unread], 4)
        XCTAssertEqual(counts.viewCounts[.read], 6)
        XCTAssertEqual(counts.viewCounts[.archive], 3)
        XCTAssertEqual(counts.viewCounts[.favorites], 2)
    }

    // Marking a non-archived row read moves it from Unread to Read; All (still
    // non-archived) and the others are untouched.
    func testApplyDeltaMovesRowFromUnreadToRead() {
        var counts = SidebarCounts()
        counts.setViewCounts(ViewCounts(all: 5, unread: 3, read: 2, archive: 0, favorites: 1))
        let old = makeReadingRow(read: false, archived: false)
        var updated = old
        updated.read = true
        counts.applyDelta(from: old, to: updated, tag: nil, rating: nil)
        XCTAssertEqual(counts.viewCounts[.unread], 2)
        XCTAssertEqual(counts.viewCounts[.read], 3)
        XCTAssertEqual(counts.viewCounts[.all], 5)
        XCTAssertEqual(counts.viewCounts[.favorites], 1)
    }

    // Faceted rule: with a #rust filter active, a row that lacks the tag is
    // outside the counted scope, so its read-toggle moves no badge.
    func testApplyDeltaIsGatedBySelectedTag() {
        var counts = SidebarCounts()
        counts.setViewCounts(ViewCounts(all: 5, unread: 3, read: 2, archive: 0, favorites: 0))
        let old = makeReadingRow(read: false, archived: false)  // no tags
        var updated = old
        updated.read = true
        counts.applyDelta(from: old, to: updated, tag: "rust", rating: nil)
        XCTAssertEqual(counts.viewCounts[.unread], 3)
        XCTAssertEqual(counts.viewCounts[.read], 2)
    }

    // The same edit on a row that *does* carry the selected tag folds normally.
    func testApplyDeltaAppliesWhenRowMatchesSelectedTag() {
        var counts = SidebarCounts()
        counts.setViewCounts(ViewCounts(all: 5, unread: 3, read: 2, archive: 0, favorites: 0))
        var old = makeReadingRow(read: false, archived: false)
        old.tags = ["rust"]
        var updated = old
        updated.read = true
        counts.applyDelta(from: old, to: updated, tag: "rust", rating: nil)
        XCTAssertEqual(counts.viewCounts[.unread], 2)
        XCTAssertEqual(counts.viewCounts[.read], 3)
    }
}
