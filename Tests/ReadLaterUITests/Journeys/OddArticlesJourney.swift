// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The odd article: real-world content variety. Real libraries hold messy,
/// varied content, and the app should degrade gracefully:
///   1. a unicode/emoji title renders in both the list row and the reader header,
///   2. an article with only the required frontmatter (no site/author/excerpt/tags)
///      renders cleanly — title and body fine, never an empty reader,
///   3. an oversized (~11 MB) body shows the "too large / Open in Browser" notice
///      instead of hanging on the parse (the reader's size guard).
final class OddArticlesJourney: UITestCase {
    private let unicodeTitle = "Café Über 日本語 🎉"

    func testOddArticlesRenderGracefully() throws {
        // The standard corpus carries the unicode and minimal articles; add the
        // oversize one (kept out of the standard corpus for its ~11 MB body). Pin
        // saved-at descending: the oversize article is newest, so the three articles
        // under test all sit near the top of the list, reachable without scrolling.
        try launchApp(articles: Fixtures.standardCorpus + [Fixtures.oversizeArticle()]) { options in
            options.pinnedDefaults["sortField"] = "savedAt"
            options.pinnedDefaults["sortAscending"] = "0"
        }

        // 1. Unicode/emoji title renders in the list row and the reader header.
        XCTAssertTrue(
            wait { list.row(Fixtures.Ids.unicode, contains: unicodeTitle) },
            "unicode title renders in the list row"
        )
        list.open(Fixtures.Ids.unicode)
        XCTAssertTrue(wait { reader.titleText == unicodeTitle }, "unicode title renders in the reader")

        // 2. Minimal article (only required frontmatter) renders cleanly: title and
        //    body are fine, with no tag chips and never the empty-reader state.
        list.open(Fixtures.Ids.minimal)
        XCTAssertTrue(wait { reader.titleText == "Minimal" }, "minimal title renders")
        XCTAssertTrue(reader.bodyContains("Just the basics"), "minimal body renders")
        XCTAssertTrue(reader.tagsText.isEmpty, "no tag metadata on the minimal article")
        XCTAssertFalse(reader.emptyState.exists, "reader shows the article, not the empty state")

        // 3. Oversize body shows the too-large notice instead of hanging on the
        //    parse, directs the reader to the browser, and still renders the title.
        //    (The notice's Open-in-Browser button doesn't surface its own a11y id on
        //    macOS — and the toolbar has an identical one — so assert its prompt text
        //    instead, which is unique to the notice.)
        list.open(Fixtures.Ids.oversize)
        XCTAssertTrue(reader.oversizeNotice.waitExists(), "too-large notice shown instead of hanging")
        XCTAssertTrue(reader.bodyContains("Open it in your browser"), "notice offers opening in the browser")
        XCTAssertTrue(wait { reader.titleText == "Oversize Article" }, "title still renders above the notice")
    }
}
