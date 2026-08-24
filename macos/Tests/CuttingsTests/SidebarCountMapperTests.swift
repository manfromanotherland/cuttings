// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The sidebar count/highlight mappers are the single crossing from the FFI
/// boundary DTOs to the presentation snapshots. These pin each field across.
final class SidebarCountMapperTests: XCTestCase {
    func testTagCountMapsFieldsAndId() {
        let tagCount = TagCount(FfiTagCount(tag: "rust", count: 7))
        XCTAssertEqual(tagCount.tag, "rust")
        XCTAssertEqual(tagCount.count, 7)
        XCTAssertEqual(tagCount.id, "rust")
    }

    func testRatingCountMapsFieldsAndId() {
        let ratingCount = RatingCount(FfiRatingCount(rating: 4, count: 9))
        XCTAssertEqual(ratingCount.rating, 4)
        XCTAssertEqual(ratingCount.count, 9)
        XCTAssertEqual(ratingCount.id, 4)
    }

    func testViewCountsMapsEveryBucket() {
        let counts = ViewCounts(FfiViewCounts(all: 1, unread: 2, read: 3, archive: 4, favorites: 5))
        XCTAssertEqual(counts.all, 1)
        XCTAssertEqual(counts.unread, 2)
        XCTAssertEqual(counts.read, 3)
        XCTAssertEqual(counts.archive, 4)
        XCTAssertEqual(counts.favorites, 5)
    }

    func testHighlightRowMapsFields() {
        let highlight = HighlightRow(FfiHighlight(id: "01HIGHLIGHT0000000000000000", text: "a passage"))
        XCTAssertEqual(highlight.id, "01HIGHLIGHT0000000000000000")
        XCTAssertEqual(highlight.text, "a passage")
    }
}
