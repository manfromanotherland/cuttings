// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Focus the board on favorites, then remove one while preserving its card and
/// file in the full library.
final class CuratingFavoritesJourney: UITestCase {
    func testFocusAndRemoveFavorite() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        list.showFavorites()
        XCTAssertTrue(list.waitForRowCount(3), "three favorites are shown")
        XCTAssertTrue(list.row(Fixtures.Ids.favoriteRead).waitExists(), "favorite is present")
        XCTAssertTrue(list.row(Fixtures.Ids.swiftTips).waitExists(), "second favorite is present")
        XCTAssertTrue(
            list.row(Fixtures.Ids.archivedFavorite).waitExists(),
            "legacy archive metadata does not hide a favorite"
        )

        list.open(Fixtures.Ids.archivedFavorite)
        reader.favoriteToggle()
        XCTAssertTrue(
            list.row(Fixtures.Ids.archivedFavorite).waitDisappears(),
            "unfavorited card leaves the focused board"
        )
        XCTAssertTrue(list.waitForRowCount(2), "favorites scope updates immediately")
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.archivedFavorite) { !$0.favorite },
            "favorite state is removed on disk"
        )

        reader.close()
        list.showAll()
        XCTAssertTrue(list.waitForRowCount(Fixtures.standardCorpus.count), "full board returns")
        XCTAssertTrue(
            list.row(Fixtures.Ids.archivedFavorite).waitExists(),
            "the card remains in the library"
        )
    }
}
