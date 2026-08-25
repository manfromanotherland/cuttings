// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The enum bridges (`Bridge/Mappers`) map the app-language library scope and
/// sort field onto the core's query enums. These tests pin every retained case, so a reordering
/// or rename on either side is caught. The `switch`es are exhaustive, so a new
/// enum case is a compile error until it is mapped.
final class EnumBridgeMapperTests: XCTestCase {
    func testLibraryScopeMapsEveryViewCase() {
        XCTAssertEqual(LibraryScope.all.ffiView, .all)
        XCTAssertEqual(LibraryScope.favorites.ffiView, .favorites)
    }

    func testReadingSortMapsEverySortCase() {
        XCTAssertEqual(ReadingSort.relevance.ffiSort, .relevance)
        XCTAssertEqual(ReadingSort.savedAt.ffiSort, .savedAt)
    }
}
