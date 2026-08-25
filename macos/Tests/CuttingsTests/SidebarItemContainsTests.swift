// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `LibraryScope.contains` mirrors the board scopes exposed by the app. Legacy
/// read/archive/favorite metadata must not hide a card now that those states
/// are no longer part of the organizing model.
final class LibraryScopeContainsTests: XCTestCase {
    func testAllContainsEveryReadingIncludingLegacyArchivedRows() {
        XCTAssertTrue(LibraryScope.all.contains(makeReadingRow()))
        XCTAssertTrue(LibraryScope.all.contains(makeReadingRow(read: true)))
        XCTAssertTrue(LibraryScope.all.contains(makeReadingRow(archived: true)))
        XCTAssertTrue(
            LibraryScope.all.contains(makeReadingRow(read: true, archived: true, favorite: true))
        )
    }

    func testMediaContainsImagesAndVideosOnly() {
        XCTAssertTrue(LibraryScope.media.contains(makeReadingRow(kind: .image)))
        XCTAssertTrue(LibraryScope.media.contains(makeReadingRow(kind: .video)))
        XCTAssertFalse(LibraryScope.media.contains(makeReadingRow(kind: .article)))
        XCTAssertFalse(LibraryScope.media.contains(makeReadingRow(kind: .quote)))
    }

    func testArticlesContainsOnlyFullArticleReadings() {
        XCTAssertTrue(LibraryScope.articles.contains(makeReadingRow(kind: .article)))
        XCTAssertFalse(
            LibraryScope.articles.contains(makeReadingRow(lightweight: true, kind: .article))
        )
        XCTAssertFalse(LibraryScope.articles.contains(makeReadingRow(kind: .image)))
    }

    func testLinksContainsOnlyLightweightArticleReadings() {
        XCTAssertTrue(
            LibraryScope.links.contains(makeReadingRow(lightweight: true, kind: .article))
        )
        XCTAssertFalse(LibraryScope.links.contains(makeReadingRow(kind: .article)))
        XCTAssertFalse(
            LibraryScope.links.contains(makeReadingRow(lightweight: true, kind: .video))
        )
    }

    func testQuotesContainsQuoteReadingsOnly() {
        XCTAssertTrue(LibraryScope.quotes.contains(makeReadingRow(kind: .quote)))
        XCTAssertFalse(LibraryScope.quotes.contains(makeReadingRow(kind: .article)))
    }
}
