// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The per-reading note control in the inspector and its Markdown editor sheet.
struct NotePage {
    let app: XCUIApplication

    var preview: XCUIElement {
        app.byId(A11y.Note.preview)
    }

    var addButton: XCUIElement {
        app.byId(A11y.Note.add)
    }

    var editButton: XCUIElement {
        app.byId(A11y.Note.edit)
    }

    var editor: XCUIElement {
        app.byId(A11y.Note.editor)
    }

    var saveButton: XCUIElement {
        app.byId(A11y.Note.save)
    }

    var deleteButton: XCUIElement {
        app.byId(A11y.Note.delete)
    }

    var editorText: String {
        editor.exists ? (editor.value as? String ?? "") : ""
    }

    func add() {
        addButton.clickWhenReady()
    }

    func edit() {
        editButton.clickWhenReady()
    }

    func type(_ markdown: String) {
        editor.clickWhenReady()
        editor.typeText(markdown)
    }

    func save() {
        saveButton.clickWhenReady()
    }

    func delete() {
        deleteButton.clickWhenReady()
    }
}
