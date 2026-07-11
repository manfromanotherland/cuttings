// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The keyboard-shortcuts cheat sheet (⌘/).
struct ShortcutsSheetPage {
    let app: XCUIApplication

    var sheet: XCUIElement { app.byId(A11y.Shortcuts.sheet) }
    var doneButton: XCUIElement { app.byId(A11y.Shortcuts.done) }

    var isVisible: Bool { sheet.exists }

    func done() { doneButton.clickWhenReady() }
}
