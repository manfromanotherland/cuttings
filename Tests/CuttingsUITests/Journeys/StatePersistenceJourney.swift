// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The app remembers where you were. It opens on Unread by default, and it
/// restores the smart view, rating filter, and search box you left active when
/// you quit — so reopening drops you straight back into the same working set.
final class StatePersistenceJourney: UITestCase {
    /// A fresh launch with nothing persisted lands on Unread, not the whole
    /// library — the pile to work through.
    func testOpensOnUnreadByDefault() throws {
        // Drop the All pin `launchApp` adds, so the app's real default view applies.
        try launchApp(articles: Fixtures.standardCorpus) { options in
            options.pinnedDefaults.removeValue(forKey: "activeView")
        }

        XCTAssertTrue(wait { sidebar.isSelected(.unread) }, "opens on the Unread view")
        XCTAssertTrue(
            list.waitForRowCount(Fixtures.Oracle.ViewCounts.unread),
            "the list shows the five unread readings, not the full library"
        )
        XCTAssertTrue(list.row(Fixtures.Ids.swift).waitExists(), "an unread reading is listed")
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitDisappears(), "a read reading is filtered out")
    }

    /// Compose a view + rating + search, quit, reopen — all three come back.
    func testViewRatingAndSearchSurviveRelaunch() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        // Narrow to the single reading that satisfies all three filters at once.
        sidebar.select(.read)
        sidebar.selectRating(5)
        list.search(Fixtures.Search.activeTerm) // "ownership" — only the read ★5 Rust article
        XCTAssertTrue(list.waitForRowCount(1), "Read ∩ ★5 ∩ \"ownership\" narrows to one reading")

        // Quit and reopen against the same library and defaults suite. `relaunchApp`
        // pins nothing, so the app has to read back what it persisted.
        relaunchApp()

        XCTAssertTrue(wait { sidebar.isSelected(.read) }, "the smart view is restored")
        XCTAssertTrue(wait { sidebar.isRatingSelected(5) }, "the rating filter is restored")
        XCTAssertTrue(
            wait { (list.searchField.value as? String) == Fixtures.Search.activeTerm },
            "the search text is restored"
        )
        XCTAssertTrue(list.waitForRowCount(1), "the composed filter is reapplied on reopen")
    }
}
