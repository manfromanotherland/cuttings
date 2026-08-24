// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `LibraryScope.contains` mirrors the two library scopes exposed by the app.
/// Legacy read/archive metadata must not hide a card now that those states are
/// no longer part of the organizing model.
final class LibraryScopeContainsTests: XCTestCase {
    func testAllContainsEveryReadingIncludingLegacyArchivedRows() {
        XCTAssertTrue(LibraryScope.all.contains(makeReadingRow()))
        XCTAssertTrue(LibraryScope.all.contains(makeReadingRow(read: true)))
        XCTAssertTrue(LibraryScope.all.contains(makeReadingRow(archived: true)))
        XCTAssertTrue(
            LibraryScope.all.contains(makeReadingRow(read: true, archived: true, favorite: true))
        )
    }

    func testFavoritesContainsOnlyFavoritesIncludingLegacyArchivedRows() {
        XCTAssertTrue(LibraryScope.favorites.contains(makeReadingRow(favorite: true)))
        XCTAssertTrue(
            LibraryScope.favorites.contains(makeReadingRow(archived: true, favorite: true))
        )
        XCTAssertFalse(LibraryScope.favorites.contains(makeReadingRow(favorite: false)))
    }
}
