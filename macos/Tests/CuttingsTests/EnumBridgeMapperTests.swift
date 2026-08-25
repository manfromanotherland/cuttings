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
        XCTAssertEqual(LibraryScope.media.ffiView, .media)
        XCTAssertEqual(LibraryScope.articles.ffiView, .articles)
        XCTAssertEqual(LibraryScope.notes.ffiView, .notes)
        XCTAssertEqual(LibraryScope.links.ffiView, .links)
        XCTAssertEqual(LibraryScope.quotes.ffiView, .quotes)
    }

    func testLibraryScopesUseToolbarOrderAndLabels() {
        XCTAssertEqual(
            LibraryScope.allCases.map(\.label),
            ["All", "Favourites", "Media", "Articles", "Notes", "Links", "Quotes"]
        )
    }

    func testLibraryScopesUseRequestedToolbarIcons() {
        XCTAssertEqual(
            LibraryScope.allCases.map(\.icon),
            [
                "asterisk", "heart", "photo.on.rectangle", "newspaper",
                "heart.text.square", "link", "quote.opening",
            ]
        )
    }

    func testReadingSortMapsEverySortCase() {
        XCTAssertEqual(ReadingSort.relevance.ffiSort, .relevance)
        XCTAssertEqual(ReadingSort.savedAt.ffiSort, .savedAt)
    }
}
