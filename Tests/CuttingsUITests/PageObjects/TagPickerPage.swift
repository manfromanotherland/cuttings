// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The modal tag picker sheet.
struct TagPickerPage {
    let app: XCUIApplication

    var searchField: XCUIElement {
        app.byId(A11y.TagPicker.searchField)
    }

    var addRow: XCUIElement {
        app.byId(A11y.TagPicker.addRow)
    }

    var doneButton: XCUIElement {
        app.byId(A11y.TagPicker.done)
    }

    var isVisible: Bool {
        searchField.exists
    }

    func row(_ tag: String) -> XCUIElement {
        app.byId(A11y.TagPicker.row(tag))
    }

    /// The picker's tag rows, top-to-bottom. Each row is a Button carrying
    /// `tagPicker.row.<tag>`; the "Add …" and "Done" buttons use other ids, so a
    /// prefix filter keeps only the tag rows in their displayed order — enough to
    /// assert the picker floats the article's own tags to the top.
    var orderedRowTags: [String] {
        let prefix = A11y.TagPicker.row("")
        var seen = Set<String>()
        var result: [String] = []
        for element in app.buttons.allElementsBoundByIndex where element.identifier.hasPrefix(prefix) {
            let tag = String(element.identifier.dropFirst(prefix.count))
            if !tag.isEmpty, seen.insert(tag).inserted {
                result.append(tag)
            }
        }
        return result
    }

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

    func done() {
        doneButton.clickWhenReady()
    }
}
