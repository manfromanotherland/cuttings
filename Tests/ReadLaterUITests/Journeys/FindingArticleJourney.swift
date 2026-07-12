// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// "Where did I put that article?": ⌘K search a distinctive term to a single
/// match, open it, clear to restore the list, then search an archived-only term
/// in All (no results — search excludes archived), switch to Archive to find it,
/// and Move to Library (unarchive), confirming counts and the file update.
final class FindingArticleJourney: UITestCase {
    func testSearchScopingAndUnarchive() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        // 1. ⌘K, search "ownership" → the single active match (the Rust article).
        keyboard.focusSearch()
        list.search(Fixtures.Search.activeTerm)
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitExists(), "match present")
        XCTAssertTrue(list.waitForRowCount(1), "narrowed to one result")

        // 2. Open it, then clear the search → the full list returns.
        list.open(Fixtures.Ids.rust)
        XCTAssertEqual(reader.titleText, "Understanding Rust Ownership")
        list.clearSearch()
        XCTAssertTrue(list.waitForRowCount(Fixtures.Oracle.ViewCounts.all), "full list restored (All 8)")

        // 3. Search an archived-only term in All → no results (All excludes archived).
        list.search(Fixtures.Search.archivedOnlyTerm)
        XCTAssertTrue(list.searchEmptyState.waitExists(), "no results in All")

        // 4. Switch to Archive → the archived article is found.
        sidebar.select(.archive)
        XCTAssertTrue(list.row(Fixtures.Ids.archived).waitExists(), "archived article found in Archive")

        // 5. Move to Library (unarchive) from the toolbar → leaves Archive, Archive
        //    2→1 and All 8→9, and the file records archived: false.
        list.open(Fixtures.Ids.archived)
        reader.unarchive()
        XCTAssertTrue(list.row(Fixtures.Ids.archived).waitDisappears(), "leaves Archive")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 1), "Archive 2→1")
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 9), "All 8→9")
        XCTAssertTrue(waitForFrontmatter(id: Fixtures.Ids.archived) { !$0.archived }, "archived: false on disk")
    }
}
