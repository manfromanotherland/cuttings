// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Revisiting the best: curating favorites. Switch to the Favorites view and
/// confirm it includes the archived favorite (favorites cross the archive
/// boundary), sort by rating descending so the highest-rated favorite floats to
/// the top, open it, then un-favorite it (⌘⇧F) and assert it leaves the view in
/// one motion with the count and the file both updated.
///
/// The three favorites and their ratings — `favoriteRead` (4), `swiftTips` (2),
/// and `archivedFavorite` (5, also archived) — give a rating-descending order of
/// `[archivedFavorite, favoriteRead, swiftTips]`, so the archived favorite is
/// both the membership proof (step 1) and the highest-rated top row (step 2).
///
/// The sort is set through the UI rather than a launch pin: pinning `sortField`
/// would shadow the in-app change via the NSArgumentDomain.
final class CuratingFavoritesJourney: UITestCase {
    private static let ratingDescOrder = [
        Fixtures.Ids.archivedFavorite, // rating 5 (archived — favorites cross archive)
        Fixtures.Ids.favoriteRead, // rating 4
        Fixtures.Ids.swiftTips // rating 2
    ]

    func testCurateFavoritesByRating() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        // 1. Switch to Favorites → all three favorites appear, including the
        //    archived one (favorites cross the archive boundary).
        sidebar.select(.favorites)
        XCTAssertTrue(sidebar.waitForCount(.favorites, equals: Fixtures.Oracle.ViewCounts.favorites), "Favorites 3")
        XCTAssertTrue(list.waitForRowCount(3), "the three favorites are listed")
        XCTAssertTrue(list.row(Fixtures.Ids.favoriteRead).waitExists(), "active favorite present")
        XCTAssertTrue(list.row(Fixtures.Ids.swiftTips).waitExists(), "unread favorite present")
        XCTAssertTrue(list.row(Fixtures.Ids.archivedFavorite).waitExists(), "archived favorite present")

        // 2. Sort by Rating, descending → highest-rated favorite on top. The
        //    archived favorite (rating 5) sorts above the active ones.
        list.selectSortField(ReadingListPage.Sort.rating)
        list.selectSortDirection(ReadingListPage.Sort.highestRated)
        XCTAssertTrue(
            wait { list.orderedRowIds == Self.ratingDescOrder },
            "favorites ordered by rating desc: [archivedFavorite(5), favoriteRead(4), swiftTips(2)]"
        )

        // 3. Open the top one and re-read → the reader shows it.
        list.open(Fixtures.Ids.archivedFavorite)
        XCTAssertEqual(reader.titleText, "Archived Favorite")

        // 4. Un-favorite it (⌘⇧F) → it leaves Favorites in one motion, the count
        //    drops 3→2, the selection advances to the next favorite, and the file
        //    records favorite: false.
        keyboard.toggleFavorite()
        XCTAssertTrue(list.row(Fixtures.Ids.archivedFavorite).waitDisappears(), "un-favorited row leaves Favorites")
        XCTAssertTrue(sidebar.waitForCount(.favorites, equals: 2), "Favorites 3→2")
        XCTAssertEqual(reader.titleText, "A Favorite Reading", "selection advanced to the next favorite")
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.archivedFavorite) { !$0.favorite },
            "favorite: false on disk"
        )
    }
}
