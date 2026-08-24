// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Capability check: full-text search edges — a no-results empty state, a
/// diacritic-insensitive match, tag values not being searched, and clearing the
/// query restoring the full list.
///
/// Queries are entered via the pasteboard (`pasteSearch`): two of them contain
/// "c", which this host drops from `typeText`; pasting sidesteps it
/// so the check can assert the real terms rather than c-free stand-ins.
final class SearchEdgeCheck: UITestCase {
    func testEmptyStateDiacriticsAndTagsNotSearched() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitExists(), "list loaded")

        // 1. A nonsense query yields the search empty state, and the sort menu stays
        //    put: an empty *result* is still a searchable list (see
        //    `showsSortControl`). Only the settled states are asserted — the blink
        //    this rule also guards against, while the debounced reload catches up
        //    with a cleared query, is too short for XCUITest to sample reliably.
        XCTAssertTrue(list.sortMenu.waitExists(), "sort menu present with a full list")
        list.pasteSearch(Fixtures.Search.noResults) // "zzzqxk"
        XCTAssertTrue(list.searchEmptyState.waitExists(), "no-results empty state")
        XCTAssertTrue(list.sortMenu.exists, "sort menu stays through a no-results search")
        list.clearSearch()
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitExists(), "clearing restores the list")
        XCTAssertTrue(list.sortMenu.exists, "sort menu present again once the list is back")

        // 2. Diacritic-insensitive: "cafe" matches "Café …" (the unicode article).
        list.pasteSearch(Fixtures.Search.diacriticQuery) // "cafe"
        XCTAssertTrue(list.row(Fixtures.Ids.unicode).waitExists(), "diacritic-insensitive match found")
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitDisappears(), "non-matching article filtered out")

        // 3. Tags aren't full-text searched: "unicode" is that article's tag, but the
        //    word appears in no title/body/excerpt — so it returns no results.
        list.pasteSearch("unicode")
        XCTAssertTrue(list.searchEmptyState.waitExists(), "tag values are not searched")

        // 4. Clearing the query restores the full list.
        list.clearSearch()
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitExists(), "clearing search restores the list")
    }
}
