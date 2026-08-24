// SPDX-License-Identifier: GPL-3.0-or-later

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
    }

    func testTagIdentityIsTheTagName() {
        XCTAssertEqual(TagCount(tag: "local-first", count: 7).id, "local-first")
    }
}
