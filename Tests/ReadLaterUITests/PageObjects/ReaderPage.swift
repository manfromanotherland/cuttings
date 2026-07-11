// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The reader (detail) column: header, body, toolbar actions, and the
/// end-of-article rating footer.
struct ReaderPage {
    let app: XCUIApplication

    // ── Header ────────────────────────────────────────────────────────────

    var title: XCUIElement { app.byId(A11y.Detail.title) }
    var tags: XCUIElement { app.byId(A11y.Detail.tags) }
    var emptyState: XCUIElement { app.byId(A11y.Detail.empty) }

    var titleText: String { title.label }

    // ── Body ──────────────────────────────────────────────────────────────
    // The Markdown body renders into AppKit text views without identifiers (out
    // of scope for E2E-4), so body assertions match on rendered text anywhere in
    // the reader.

    func bodyContains(_ text: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", text, text)
        return app.descendants(matching: .any).matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }

    /// Whether any image is present in the reader (the kitchen-sink asset).
    var hasImage: Bool { app.images.firstMatch.exists }

    // ── Oversize guard ──────────────────────────────────────────────────────

    var oversizeNotice: XCUIElement { app.byId(A11y.Detail.oversize) }
    var oversizeOpenInBrowserButton: XCUIElement { app.byId(A11y.Detail.oversizeOpenInBrowser) }

    // ── Toolbar actions ─────────────────────────────────────────────────────

    func markReadToggle() { app.byId(A11y.Toolbar.markRead).clickWhenReady() }
    func favoriteToggle() { app.byId(A11y.Toolbar.favorite).clickWhenReady() }
    func archive() { app.byId(A11y.Toolbar.archive).clickWhenReady() }
    func unarchive() { app.byId(A11y.Toolbar.unarchive).clickWhenReady() }
    func openInBrowser() { app.byId(A11y.Toolbar.openInBrowser).clickWhenReady() }
    func openTagPicker() { app.byId(A11y.Toolbar.tags).clickWhenReady() }
    func toggleHighlights() { app.byId(A11y.Toolbar.highlights).clickWhenReady() }
    func delete() { app.byId(A11y.Toolbar.delete).clickWhenReady() }

    // ── Rating footer ─────────────────────────────────────────────────────

    func star(_ n: Int) -> XCUIElement { app.byId(A11y.RatingFooter.star(n)) }

    func rate(_ n: Int) {
        scrollToFooter()
        star(n).clickWhenReady()
    }

    /// Scroll the reader to reveal the end-of-article rating footer.
    @discardableResult
    func scrollToFooter(timeout: TimeInterval = 8) -> Bool {
        let anchor = star(5)
        let deadline = Date().addingTimeInterval(timeout)
        while !anchor.exists {
            if Date() >= deadline { return false }
            app.scrollViews.firstMatch.swipeUp()
        }
        return true
    }
}
