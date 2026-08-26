// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Capability checks for a complete large-library board snapshot. XCUITest
/// exposes every loaded row to accessibility, so the useful assertions are that
/// the whole corpus is reachable and shares one continuous masonry layout.
final class LargeLibraryCheck: UITestCase {
    func testToolbarAppearsBeforeLibraryHydrationFinishes() throws {
        try launchAppWithoutWaiting(articles: [Fixtures.standardCorpus[0]]) { options in
            options.environment["CUTTINGS_TEST_LIBRARY_HYDRATION_DELAY_MS"] = "3000"
        }

        XCTAssertTrue(
            list.searchField.waitForExistence(timeout: 1.5),
            "search should be usable while the library hydrates"
        )
        XCTAssertTrue(
            list.filterGroup.waitForExistence(timeout: 1.5),
            "the type filter should be usable while the library hydrates"
        )
        XCTAssertTrue(
            app.byId(A11y.List.cardSizeControl).waitForExistence(timeout: 1.5),
            "zoom controls should be usable while the library hydrates"
        )
    }

    func testWarmLaunchShowsCachedCardBeforeReconciliation() throws {
        let expected = Fixtures.standardCorpus[0]
        try launchApp(articles: [expected])

        relaunchAppWithoutWaiting { options in
            options.environment["CUTTINGS_TEST_TRUSTED_CACHE_LIBRARY"] = library.libraryURL.path
            options.environment["CUTTINGS_TEST_LIBRARY_RECONCILIATION_DELAY_MS"] = "3000"
        }

        XCTAssertTrue(
            list.row(expected.id).waitForExistence(timeout: 1.5),
            "a warm launch should show the cached card before file reconciliation"
        )
    }

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
