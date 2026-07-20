// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The highlights inspector panel.
struct HighlightsPage {
    let app: XCUIApplication

    var list: XCUIElement { app.byId(A11y.Highlights.list) }
    var emptyState: XCUIElement { app.byId(A11y.Highlights.emptyState) }

    func row(_ highlightId: String) -> XCUIElement { app.byId(A11y.Highlights.row(highlightId)) }

    /// The number of highlight rows currently listed.
    var rowCount: Int {
        app.allByIdPrefix(A11y.Highlights.row("")).count
    }

    /// Delete a highlight via its row's × button. That button carries the row's
    /// identifier (with label "Close") and is only visible on hover, so hover the
    /// row's text to reveal it, then click the button — filtered from the row's
    /// static text by element type.
    func delete(_ highlightId: String) {
        let identifier = A11y.Highlights.row(highlightId)
        app.staticTexts.matching(identifier: identifier).firstMatch.hover()
        app.buttons.matching(identifier: identifier).firstMatch.clickWhenReady()
    }
}
