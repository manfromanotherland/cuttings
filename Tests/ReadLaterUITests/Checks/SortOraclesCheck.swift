// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Capability check: every sort field, ascending and descending, produces the
/// exact row order — including NULLs-last for `read_at`/`word_count` and the
/// `id`-DESC tiebreak — against the hand-computed oracles in `Fixtures.Oracle`.
final class SortOraclesCheck: UITestCase {
    private typealias Menu = ReadingListPage.Sort
    private typealias Order = Fixtures.Oracle.Sort

    /// One sort field + direction and the row order it must produce.
    private struct SortCase {
        let field: String
        let direction: String
        let order: [String]
        let name: String
        init(_ field: String, _ direction: String, _ order: [String], _ name: String) {
            self.field = field
            self.direction = direction
            self.order = order
            self.name = name
        }
    }

    func testEverySortFieldAscendingAndDescending() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        // Keep a tiny article open so the row-order enumeration never races a large
        // reader; it stays selected across sorts (it's in every All-view list).
        list.open(Fixtures.Ids.minimal)

        let cases = [
            SortCase(Menu.dateSaved, Menu.newestFirst, Order.savedAtDescending, "saved-at desc"),
            SortCase(Menu.dateSaved, Menu.oldestFirst, Order.savedAtAscending, "saved-at asc"),
            SortCase(Menu.dateRead, Menu.readMostRecently, Order.readAtDescending, "read-at desc"),
            SortCase(Menu.dateRead, Menu.readLeastRecently, Order.readAtAscending, "read-at asc"),
            SortCase(Menu.rating, Menu.highestRated, Order.ratingDescending, "rating desc"),
            SortCase(Menu.rating, Menu.lowestRated, Order.ratingAscending, "rating asc"),
            SortCase(Menu.timeToRead, Menu.longestFirst, Order.wordCountDescending, "word-count desc"),
            SortCase(Menu.timeToRead, Menu.shortestFirst, Order.wordCountAscending, "word-count asc")
        ]

        for sortCase in cases {
            list.selectSortField(sortCase.field)
            list.selectSortDirection(sortCase.direction)
            XCTAssertTrue(wait { list.orderedRowIds == sortCase.order }, "order for \(sortCase.name)")
        }
    }
}
