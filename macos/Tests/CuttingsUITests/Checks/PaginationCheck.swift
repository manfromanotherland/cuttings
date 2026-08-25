// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Capability check: the list pages past its 60-row window. `bulkCorpus(120)`
/// exceeds one page, so the oldest article (row 120) is only reachable once
/// `loadMore` has fetched the second page — a pager that stopped at the first
/// page would never surface it.
///
/// Note: XCUITest exposes every *loaded* row to accessibility (not just the
/// visible ones), and materializing them drives `loadMore` to completion — so
/// "first page only" isn't observable here. The meaningful assertion is that the
/// whole corpus becomes reachable.
final class PaginationCheck: UITestCase {
    func testLoadsEveryPage() throws {
        try launchApp(articles: Fixtures.bulkCorpus(count: 120))
        XCTAssertTrue(list.row(Fixtures.id(119)).waitExists(), "newest article heads the list")

        // The oldest article (row 120) is only present once loadMore has paged past
        // the 60-row first page.
        XCTAssertTrue(list.scrollToRow(Fixtures.id(0)), "loadMore pages through to the oldest article")
    }
}
