// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// A proper deep read: open the long kitchen-sink article, confirm its
/// markdown blocks and asset image render, zoom the image in the full-screen
/// lightbox, bump the text size (⌘+) and switch to Serif live, scroll to the
/// end, rate it 5 stars, and favorite it — verifying the rating and favorite
/// land on disk.
///
/// Notes: font/size changes can't be inspected pixel-by-pixel in XCUITest, so the
/// font switch is verified by the persisted `readerFont` preference and ⌘+ is
/// exercised for no-crash/live behavior. Code and table blocks may render into
/// non-text AppKit views, so a representative set of textual blocks is asserted.
/// The typography steps are done *after* rate/favorite: this build's appearance
/// popover doesn't dismiss on an outside click, so opening it last keeps it from
/// blocking the reader interactions. (All these actions are independent.)
final class DeepReadJourney: UITestCase {
    func testDeepReadRateAndFavorite() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        // The kitchen-sink body references an inline asset image; write it so the
        // reader can load it (assets aren't indexed, just read on render).
        try library.writeAsset(
            articleId: Fixtures.Ids.kitchenSink,
            fileName: PNGFixture.fileName,
            data: PNGFixture.data
        )

        // 1. Open the long article; its blocks + asset image render natively.
        list.open(Fixtures.Ids.kitchenSink)
        XCTAssertEqual(reader.titleText, "The Complete Markdown Sample")
        XCTAssertTrue(reader.bodyContains("First bullet"), "bullet list")
        XCTAssertTrue(reader.bodyContains("First step"), "ordered list")
        XCTAssertTrue(reader.bodyContains("Unchecked task"), "task list")
        XCTAssertTrue(reader.bodyContains("Plain files outlive"), "blockquote")
        XCTAssertTrue(reader.bodyContains("Sample image"), "asset image caption")

        // 1b. Click the figure to zoom it: the full-screen lightbox opens, and
        //     Escape dismisses it.
        XCTAssertTrue(reader.revealFigure(), "figure scrolled into view")
        reader.openImageZoom()
        XCTAssertTrue(reader.lightboxImage.waitExists(), "image zoom lightbox opened")
        keyboard.escape()
        XCTAssertTrue(reader.lightboxImage.waitDisappears(), "lightbox dismissed with Escape")

        // 2. Scroll to the end and rate 5 stars → ★5 sidebar bucket updates (rust
        //    already has one, so it becomes 2), rating: 5 on disk.
        XCTAssertTrue(reader.scrollToFooter(), "rating footer reachable at the bottom")
        reader.star(5).clickWhenReady()
        XCTAssertTrue(sidebar.waitForRatingCount(5, equals: 2), "★5 bucket now has 2")
        XCTAssertTrue(waitForFrontmatter(id: Fixtures.Ids.kitchenSink) { $0.rating == 5 }, "rating: 5 on disk")

        // 3. Favorite it → Favorites 3→4, favorite: true on disk.
        reader.favoriteToggle()
        XCTAssertTrue(sidebar.waitForCount(.favorites, equals: 4), "Favorites 3→4")
        XCTAssertTrue(waitForFrontmatter(id: Fixtures.Ids.kitchenSink) { $0.favorite }, "favorite on disk")

        // 4. Bump the text size twice (⌘+) — reflows live, reader stays put.
        keyboard.increaseFontSize()
        keyboard.increaseFontSize()
        XCTAssertEqual(reader.titleText, "The Complete Markdown Sample", "reader intact after resize")

        // 5. Switch the reader font to Serif — verified via the persisted setting.
        //    Done last: this build's popover doesn't dismiss on an outside click,
        //    and leaving it open at the end blocks nothing.
        sidebar.setFont("Serif")
        XCTAssertTrue(sidebar.waitForFontValue("Serif"), "reader font switched to Serif")
    }
}
