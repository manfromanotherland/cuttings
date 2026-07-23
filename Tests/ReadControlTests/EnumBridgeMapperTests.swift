// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The enum bridges (`Bridge/Mappers`) map the app-language smart view and sort
/// field onto the core's query enums. These tests pin every case, so a reordering
/// or rename on either side is caught. The `switch`es are exhaustive, so a new
/// enum case is a compile error until it is mapped.
final class EnumBridgeMapperTests: XCTestCase {

    func testSidebarItemMapsEveryViewCase() {
        XCTAssertEqual(SidebarItem.all.ffiView, .all)
        XCTAssertEqual(SidebarItem.unread.ffiView, .unread)
        XCTAssertEqual(SidebarItem.read.ffiView, .read)
        XCTAssertEqual(SidebarItem.archive.ffiView, .archive)
        XCTAssertEqual(SidebarItem.favorites.ffiView, .favorites)
    }

    func testReadingSortMapsEverySortCase() {
        XCTAssertEqual(ReadingSort.relevance.ffiSort, .relevance)
        XCTAssertEqual(ReadingSort.savedAt.ffiSort, .savedAt)
        XCTAssertEqual(ReadingSort.readAt.ffiSort, .readAt)
        XCTAssertEqual(ReadingSort.rating.ffiSort, .rating)
        // "Time to read" is derived from the core's word count.
        XCTAssertEqual(ReadingSort.timeToRead.ffiSort, .wordCount)
    }
}
