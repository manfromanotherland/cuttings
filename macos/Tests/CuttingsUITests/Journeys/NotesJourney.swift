// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Personal notes stay plain Markdown on disk, survive reopening, cancel cleanly
/// with Escape, and refresh when a sync tool edits `note.md` directly.
final class NotesJourney: UITestCase {
    func testAddReopenCancelAndDeleteNote() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        let id = Fixtures.Ids.minimal
        let markdown = "## Follow up\n\n- Ask about the **details**."

        list.open(id)
        noteEditor.add()
        noteEditor.type(markdown)
        noteEditor.save()

        XCTAssertTrue(
            wait { self.library.noteContents(articleId: id) == markdown },
            "raw Markdown saved to note.md"
        )

        keyboard.escape()
        XCTAssertTrue(noteEditor.editButton.waitDisappears(), "reading overlay closed")
        list.open(id)
        noteEditor.edit()
        XCTAssertTrue(noteEditor.editorText.contains("## Follow up"), "saved Markdown reopened")

        noteEditor.type("\n\nUnsaved change")
        keyboard.escape()
        XCTAssertTrue(noteEditor.editor.waitDisappears(), "Escape cancelled the editor")
        XCTAssertEqual(library.noteContents(articleId: id), markdown, "cancel left the file untouched")

        noteEditor.edit()
        noteEditor.delete()
        app.tapDialogButton("Delete note")
        XCTAssertTrue(wait { !self.library.noteExists(articleId: id) }, "blank note removed note.md")
        XCTAssertTrue(noteEditor.addButton.waitExists(), "inspector returned to Add note")
    }

    func testExternalNoteEditRefreshesAndProtectsTheDraft() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        let id = Fixtures.Ids.minimal
        let first = "# Synced note\n\nWritten outside Cuttings."
        let newer = "# Newer synced note\n\nChanged on another device."

        list.open(id)
        try library.writeNote(articleId: id, markdown: first)
        XCTAssertTrue(noteEditor.editButton.waitExists(), "external note appeared in the inspector")

        noteEditor.edit()
        XCTAssertTrue(noteEditor.editorText.contains("# Synced note"), "external Markdown loaded")
        noteEditor.type("\n\nMy draft")

        try library.writeNote(articleId: id, markdown: newer)
        app.tapDialogButton("Load latest version")
        XCTAssertTrue(
            wait { self.noteEditor.editorText.contains("# Newer synced note") },
            "newer disk version loaded instead of being overwritten"
        )
    }
}
