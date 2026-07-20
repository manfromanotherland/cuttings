// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Morning catch-up: boot an existing seeded library, confirm the sidebar
/// counts match the oracles, switch to Unread and see only the unread articles
/// with their row content (title, site, reading time, excerpt, unread indicator).
///
/// Note: the list row does not render author or tag
/// chips (those appear in the reader), and the reading-time "raw word count"
/// tooltip is a hover tooltip in the reader that XCUITest can't query — so this
/// asserts the reading-time label instead.
final class MorningCatchUpJourney: UITestCase {
    func testBootCountsThenSkimUnread() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        // 1. Counts match the oracles.
        let counts = Fixtures.Oracle.ViewCounts.self
        XCTAssertTrue(sidebar.waitForCount(.all, equals: counts.all), "All")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: counts.unread), "Unread")
        XCTAssertTrue(sidebar.waitForCount(.read, equals: counts.read), "Read")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: counts.archive), "Archive")
        XCTAssertTrue(sidebar.waitForCount(.favorites, equals: counts.favorites), "Favorites")

        // 2. Switch to Unread → only the 5 unread articles; read/archived are gone.
        sidebar.select(.unread)
        XCTAssertTrue(list.waitForRowCount(counts.unread), "Unread shows 5 rows")
        XCTAssertTrue(list.row(Fixtures.Ids.swift).waitExists(), "Unread article present")
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitDisappears(), "Read article gone from Unread")
        XCTAssertTrue(list.row(Fixtures.Ids.archived).waitDisappears(), "Archived article gone from Unread")

        // 3. Row content for the Swift article: title, site, reading time,
        //    excerpt, and the unread indicator — all tied to its row.
        let swift = Fixtures.Ids.swift
        XCTAssertTrue(list.row(swift, contains: "Swift Concurrency"), "title")
        XCTAssertTrue(list.row(swift, contains: "swift.org"), "site")
        XCTAssertTrue(list.row(swift, contains: "13 min read"), "reading time (2500 words @ 200 wpm)")
        XCTAssertTrue(list.row(swift, contains: "Structured"), "excerpt")
        XCTAssertTrue(list.rowHasIndicator(swift, label: "Unread"), "unread indicator")

        // 4. Opening the article, the reader shows the reading-time label (the raw
        //    word-count tooltip is a hover tooltip, not automatable — see note).
        list.open(swift)
        XCTAssertEqual(reader.titleText, "Swift Concurrency Explained")
        XCTAssertTrue(app.staticTexts["13 min read"].exists, "reader shows reading time")
    }
}
