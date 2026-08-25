// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Capability checks for a complete large-library board snapshot. XCUITest
/// exposes every loaded row to accessibility, so the useful assertions are that
/// the whole corpus is reachable and shares one continuous masonry layout.
final class LargeLibraryCheck: UITestCase {
    func testCompleteSnapshotReachesOldestCard() throws {
        try launchApp(articles: Fixtures.bulkCorpus(count: 120))
        XCTAssertTrue(list.row(Fixtures.id(119)).waitExists(), "newest article heads the list")
        XCTAssertTrue(list.scrollToRow(Fixtures.id(0)), "the oldest article remains reachable")
    }

    func testSnapshotUsesOneContinuousMasonryLayout() throws {
        try launchApp(articles: Fixtures.continuousMasonryCorpus())

        let tallCard = list.row(Fixtures.id(1))
        let laterCard = list.row(Fixtures.id(0))
        XCTAssertTrue(list.scrollToRow(Fixtures.id(0)), "the final card becomes reachable")
        XCTAssertTrue(tallCard.exists)
        XCTAssertTrue(laterCard.exists)

        XCTAssertLessThan(
            laterCard.frame.minY,
            tallCard.frame.maxY,
            "later cards should fill shorter columns instead of starting a new horizontal band"
        )
    }
}
