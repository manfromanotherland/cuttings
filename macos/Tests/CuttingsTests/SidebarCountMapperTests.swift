// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Filter/highlight mappers are the single crossing from the FFI boundary DTOs
/// to presentation snapshots. These pin each retained field across.
final class FilterMapperTests: XCTestCase {
    func testTagCountMapsFieldsAndId() {
        let tagCount = TagCount(FfiTagCount(tag: "rust", count: 7))
        XCTAssertEqual(tagCount.tag, "rust")
        XCTAssertEqual(tagCount.count, 7)
        XCTAssertEqual(tagCount.id, "rust")
    }

    func testHighlightRowMapsFields() {
        let highlight = HighlightRow(FfiHighlight(id: "01HIGHLIGHT0000000000000000", text: "a passage"))
        XCTAssertEqual(highlight.id, "01HIGHLIGHT0000000000000000")
        XCTAssertEqual(highlight.text, "a passage")
    }
}
