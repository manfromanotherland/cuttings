// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

/// The lightweight filter state retained by the library board: available tags
/// and their stable identities.
final class LibraryFiltersTests: XCTestCase {
    func testStartsWithNoTags() {
        XCTAssertTrue(LibraryFilters().tags.isEmpty)
    }

    func testStoresTagCountsWithoutSidebarState() {
        let filters = LibraryFilters(tags: [
            TagCount(tag: "rust", count: 3),
            TagCount(tag: "swift", count: 2)
        ])

        XCTAssertEqual(filters.tags.map(\.tag), ["rust", "swift"])
        XCTAssertEqual(filters.tags.map(\.count), [3, 2])
        XCTAssertEqual(filters.searchTagCandidates.map(\.token.value), ["rust", "swift"])
    }

    func testTagIdentityUsesTheExactNameBytes() {
        XCTAssertEqual(
            TagCount(tag: "local-first", count: 7).id,
            Data("local-first".utf8)
        )
    }

    func testCanonicalUnicodeVariantsRemainDistinctSnapshots() {
        let precomposed = TagCount(tag: "Café", count: 1)
        let decomposed = TagCount(tag: "Cafe\u{301}", count: 1)

        XCTAssertNotEqual(precomposed, decomposed)
        XCTAssertNotEqual(precomposed.id, decomposed.id)
    }
}
