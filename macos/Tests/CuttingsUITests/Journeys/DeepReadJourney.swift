// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Open a long article from the board, exercise native Markdown and image zoom,
/// then favorite it from the inspector.
final class DeepReadJourney: UITestCase {
    func testDeepReadZoomAndFavorite() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        try library.writeAsset(
            articleId: Fixtures.Ids.kitchenSink,
            fileName: PNGFixture.fileName,
            data: PNGFixture.data
        )

        list.open(Fixtures.Ids.kitchenSink)
        XCTAssertEqual(reader.titleText, "The Complete Markdown Sample")
        XCTAssertTrue(reader.bodyContains("First bullet"), "bullet list")
        XCTAssertTrue(reader.bodyContains("First step"), "ordered list")
        XCTAssertTrue(reader.bodyContains("Unchecked task"), "task list")
        XCTAssertTrue(reader.bodyContains("Plain files outlive"), "blockquote")
        XCTAssertTrue(reader.bodyContains("Sample image"), "asset image caption")

        XCTAssertTrue(reader.revealFigure(), "figure scrolled into view")
        reader.openImageZoom()
        XCTAssertTrue(reader.lightboxImage.waitExists(), "image zoom lightbox opened")
        keyboard.escape()
        XCTAssertTrue(reader.lightboxImage.waitDisappears(), "lightbox dismissed with Escape")

        reader.favoriteToggle()
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.kitchenSink) { $0.favorite },
            "favorite state is written on disk"
        )

        keyboard.increaseFontSize()
        keyboard.increaseFontSize()
        XCTAssertEqual(reader.titleText, "The Complete Markdown Sample", "reader remains open after resize")
    }
}
