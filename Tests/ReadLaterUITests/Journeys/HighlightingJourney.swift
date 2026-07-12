// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Reading with a highlighter: an article seeded with two highlights on
/// disk. Open the highlights inspector (⌘⇧H) and see both, delete the first (the
/// file keeps the second), then delete the last (empty state + the highlights
/// file removed from disk entirely).
///
/// Creating a highlight needs a drag-select in the reader, which XCUITest can't
/// drive reliably — so this seeds highlights and exercises viewing + deletion,
/// the deterministic parts.
final class HighlightingJourney: UITestCase {
    func testViewAndDeleteHighlights() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        let article = Fixtures.Highlights.articleId
        let first = Fixtures.Highlights.seeded[0]
        let second = Fixtures.Highlights.seeded[1]
        try library.writeHighlights(articleId: article, Fixtures.Highlights.seeded)

        // 1. Open the article and its highlights inspector (⌘⇧H): both listed.
        list.open(article)
        keyboard.toggleHighlights()
        XCTAssertTrue(highlightsInspector.row(first.id).waitExists(), "first highlight listed")
        XCTAssertTrue(highlightsInspector.row(second.id).exists, "second highlight listed")
        XCTAssertEqual(highlightsInspector.rowCount, 2, "two highlights")

        // 2. Delete the first → list drops to one; the file keeps the second only.
        highlightsInspector.delete(first.id)
        XCTAssertTrue(highlightsInspector.row(first.id).waitDisappears(), "first highlight removed")
        XCTAssertTrue(highlightsInspector.row(second.id).exists, "second highlight remains")
        XCTAssertEqual(highlightsInspector.rowCount, 1, "one highlight left")
        XCTAssertTrue(
            wait {
                guard let contents = library.highlightsContents(articleId: article) else { return false }
                return contents.contains(second.text) && !contents.contains(first.text)
            },
            "file keeps only the second highlight"
        )

        // 3. Delete the last → empty state, and the highlights file is gone.
        highlightsInspector.delete(second.id)
        XCTAssertTrue(highlightsInspector.emptyState.waitExists(), "empty state shown")
        XCTAssertTrue(
            wait { !library.highlightsExist(articleId: article) },
            "highlights file removed from disk"
        )
    }
}
