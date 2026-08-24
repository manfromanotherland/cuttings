// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Capability check: the toolbar's Highlight button acts on the selection rather
/// than opening the inspector, and says so when there's nothing selected. The
/// inspector stays reachable through ⌘⇧H.
///
/// Only the no-selection path is driven here: creating a highlight needs a
/// drag-select in the reader, which XCUITest can't drive reliably (see
/// `HighlightingJourney`).
final class HighlightActionCheck: UITestCase {
    func testHighlightButtonPromptsWithoutSelectionAndDoesNotOpenInspector() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        list.open(Fixtures.Highlights.articleId)
        XCTAssertTrue(reader.title.waitExists(), "article opened")

        // 1. Nothing selected → a hint, and the inspector stays shut.
        reader.highlightSelection()
        XCTAssertTrue(reader.highlightHint.waitExists(), "hint shown with no selection")
        XCTAssertFalse(highlightsInspector.emptyState.exists, "button did not open the inspector")

        // 2. ⌘⇧H still opens the inspector — this article has no highlights yet,
        //    so it shows its empty state. Dismiss the hint first: an open popover
        //    would swallow the key equivalent.
        keyboard.escape()
        XCTAssertTrue(reader.highlightHint.waitDisappears(), "hint dismissed")
        keyboard.toggleHighlights()
        XCTAssertTrue(highlightsInspector.emptyState.waitExists(), "⌘⇧H still opens the inspector")
    }
}
