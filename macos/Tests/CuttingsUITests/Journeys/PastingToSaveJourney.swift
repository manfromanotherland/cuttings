// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest

/// Paste-to-save contract: the board imports plain text exactly once, while the
/// same shortcut keeps its native editing behavior when the search field owns
/// focus.
final class PastingToSaveJourney: UITestCase {
    func testPlainTextPasteSavesDeduplicatesAndRespectsSearchFocus() throws {
        try launchApp()

        let cutting = "A durable pasted cutting for the ingestion journey."
        XCTAssertTrue(list.emptyState.waitExists(), "empty board is ready")

        // 1. Paste plain text onto the empty board. The real app/core path adds
        //    one visible row and one article.md to the isolated library.
        paste(cutting, afterClicking: list.emptyState)
        XCTAssertTrue(list.waitForRowCount(1), "paste creates exactly one row")
        XCTAssertTrue(wait { self.articleFiles.count == 1 }, "paste creates one on-disk reading")

        let savedRowIDs = list.orderedRowIds
        let savedArticle = try XCTUnwrap(articleFiles.first)
        try XCTAssertTrue(
            String(contentsOf: savedArticle, encoding: .utf8).contains(cutting),
            "the saved reading contains the pasted text"
        )

        // 2. Re-pasting the identical value resolves as a duplicate. Wait for
        //    that acknowledgement so the unchanged-count assertions cannot race
        //    the asynchronous item-provider/core work.
        paste(cutting)
        XCTAssertTrue(
            wait { self.app.byId(A11y.Save.notice).label.contains("Already saved") },
            "duplicate paste is acknowledged"
        )
        XCTAssertTrue(list.waitForRowCount(1), "duplicate leaves exactly one row")
        XCTAssertEqual(list.orderedRowIds, savedRowIDs)
        XCTAssertEqual(articleFiles, [savedArticle], "duplicate leaves exactly one on-disk reading")

        // 3. Once search owns focus, ⌘V belongs to its field editor. Waiting
        //    for the previous notice to leave lets any accidental import surface
        //    a fresh notice during the assertion window below.
        XCTAssertTrue(app.byId(A11y.Save.notice).waitDisappears(6), "duplicate notice clears")
        let query = "search-only-paste"
        list.pasteSearch(query)
        XCTAssertTrue(wait { (self.list.searchField.value as? String) == query }, "search receives paste")
        XCTAssertTrue(list.waitForRowCount(0), "pasted search filters the existing row")
        XCTAssertFalse(
            app.byId(A11y.Save.notice).waitForExistence(timeout: 1),
            "search paste does not trigger board ingestion"
        )
        XCTAssertEqual(articleFiles, [savedArticle], "search paste leaves the library unchanged")
    }

    private var articleFiles: [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: library.articlesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "article.md" }
            .sorted { $0.path < $1.path }
    }

    private func paste(_ text: String, afterClicking target: XCUIElement? = nil) {
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(text, forType: .string))
        target?.clickWhenReady()
        app.typeKey("v", modifierFlags: .command)
    }
}
