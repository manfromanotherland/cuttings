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

    /// Delete a highlight via its row context menu (matching the journey).
    func delete(_ highlightId: String) {
        row(highlightId).rightClick()
        app.menuItems["Delete"].clickWhenReady()
    }
}
