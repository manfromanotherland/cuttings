// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Bring-up smoke test: proves the whole plumbing works on a real Mac before the
/// journey suite is built on it. Launch against the seeded corpus, confirm the
/// sidebar counts match the oracles, open an article and see its title, then
/// search a real term and get exactly one row. If this is green, the harness,
/// fixtures, identifiers, and page objects all line up with the real app.
final class SmokeTest: UITestCase {
    func testLaunchCountsOpenAndSearch() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        // 1. The five sidebar counts equal the exported oracles.
        let counts = Fixtures.Oracle.ViewCounts.self
        XCTAssertTrue(sidebar.waitForCount(.all, equals: counts.all), "All count")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: counts.unread), "Unread count")
        XCTAssertTrue(sidebar.waitForCount(.read, equals: counts.read), "Read count")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: counts.archive), "Archive count")
        XCTAssertTrue(sidebar.waitForCount(.favorites, equals: counts.favorites), "Favorites count")

        // 2. Open a known article and confirm the reader shows its title.
        list.open(Fixtures.Ids.rust)
        XCTAssertTrue(reader.title.waitExists(), "Reader title should appear")
        XCTAssertEqual(reader.titleText, "Understanding Rust Ownership")

        // 3. Search a distinctive real term ("ownership" appears only in the Rust
        //    article): the Rust row stays, a known non-match disappears, and the
        //    list settles at exactly one row.
        list.search(Fixtures.Search.activeTerm)
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitExists(), "Rust article should match")
        XCTAssertTrue(list.row(Fixtures.Ids.swift).waitDisappears(), "Non-matching article should be gone")
        XCTAssertTrue(list.waitForRowCount(1), "Search should narrow to exactly one row")
        XCTAssertEqual(list.orderedRowIds, [Fixtures.Ids.rust])
    }
}
