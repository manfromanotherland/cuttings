// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The modal tag picker sheet.
struct TagPickerPage {
    let app: XCUIApplication

    var searchField: XCUIElement { app.byId(A11y.TagPicker.searchField) }
    var addRow: XCUIElement { app.byId(A11y.TagPicker.addRow) }
    var doneButton: XCUIElement { app.byId(A11y.TagPicker.done) }

    var isVisible: Bool { searchField.exists }

    func row(_ tag: String) -> XCUIElement { app.byId(A11y.TagPicker.row(tag)) }

    func type(_ text: String) {
        searchField.clickWhenReady()
        searchField.typeText(text)
    }

    /// Type a brand-new tag name and apply it via the "Add …" row.
    func createAndApply(_ tag: String) {
        type(tag)
        addRow.clickWhenReady()
    }

    /// Toggle an existing tag on or off.
    func toggle(_ tag: String) {
        row(tag).clickWhenReady()
    }

    func done() { doneButton.clickWhenReady() }
}
