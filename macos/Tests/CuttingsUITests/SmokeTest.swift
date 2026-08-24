// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Bring-up smoke test for the sidebar-free board: load every seeded card,
/// open one, search to a single result, and delete it.
final class SmokeTest: UITestCase {
    func testLaunchBoardOpenSearchAndDelete() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        // Legacy read/archive metadata does not remove cards from the board.
        XCTAssertTrue(list.waitForRowCount(Fixtures.standardCorpus.count), "all cards loaded")
        XCTAssertTrue(list.row(Fixtures.Ids.archived).waitExists(), "legacy archived card is visible")
        XCTAssertTrue(app.byId(A11y.Filter.favorites).exists, "favorites control is available")
        XCTAssertTrue(app.byId(A11y.Filter.menu).exists, "filter control is available")

        // Open a known article and confirm the overlay shows its title.
        list.open(Fixtures.Ids.rust)
        XCTAssertTrue(reader.title.waitExists(), "Reader title should appear")
        XCTAssertEqual(reader.titleText, "Understanding Rust Ownership")
        reader.close()

        // "ownership" appears only in the Rust article.
        list.search(Fixtures.Search.activeTerm)
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitExists(), "Rust article should match")
        XCTAssertTrue(list.row(Fixtures.Ids.swift).waitDisappears(), "Non-matching article should be gone")
        XCTAssertTrue(list.waitForRowCount(1), "Search should narrow to exactly one row")
        XCTAssertEqual(list.orderedRowIds, [Fixtures.Ids.rust])

        // Delete the filtered card and verify both the board and source-of-truth file.
        list.open(Fixtures.Ids.rust)
        reader.delete()
        list.confirmDelete()
        XCTAssertTrue(list.waitForRowCount(0), "Deleted card should leave the filtered board")
        XCTAssertTrue(wait { !library.articleExists(id: Fixtures.Ids.rust) }, "Deleted card file should be removed")
    }
}
