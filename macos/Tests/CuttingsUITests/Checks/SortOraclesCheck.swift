// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Capability check: the board uses its fixed newest-saved-first ordering.
final class BoardOrderCheck: UITestCase {
    func testNewestSavedCardAppearsFirst() throws {
        try launchApp(articles: Fixtures.standardCorpus) { options in
            // A retired preference must not change the now-fixed board order.
            options.pinnedDefaults["sortField"] = "timeToRead"
            options.pinnedDefaults["sortAscending"] = "1"
        }

        XCTAssertTrue(wait { !list.orderedRowIds.isEmpty }, "board loads saved cards")
        let visibleIDs = list.orderedRowIds
        XCTAssertEqual(
            visibleIDs,
            visibleIDs.sorted(by: >),
            "board uses newest-saved-first ordering"
        )
        XCTAssertFalse(app.byId("list.sort").exists, "retired sort control stays absent")
    }
}
