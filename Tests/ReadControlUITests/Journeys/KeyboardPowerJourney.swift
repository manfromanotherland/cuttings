// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Keyboard-only power run. A power user blasts through the Unread pile
/// without ever touching the mouse: arrow-key navigation with the reader
/// following each selection, ⌘U / ⌘⇧F / ⌘⌫ acting on the selected row, ⌘K to jump
/// to search and Escape back, ⌘/ for the shortcuts cheat sheet, ⌃⌘S to toggle
/// the sidebar, and ⌘⇧R for focus mode — the full keyboard surface in one flow.
///
/// The sort is pinned (saved-at descending) so the Unread order is deterministic
/// regardless of the machine's persisted preference:
///   swiftTips(7) → minimal(4) → unicode(3) → kitchenSink(2) → swift(1)
/// The triage beats (one-motion removal, live counts, on-disk truth) mirror the
/// toolbar-driven `InboxZeroJourney`; here every one is reached from the keyboard.
final class KeyboardPowerJourney: UITestCase {
    private let unicodeTitle = "Café Über 日本語 🎉"
    private let kitchenSinkTitle = "The Complete Markdown Sample"

    // One continuous keyboard-only walk; asserting every beat keeps it over the limit.
    // swiftlint:disable:next function_body_length
    func testDriveTheQueueFromTheKeyboard() throws {
        // Pin the sort so the Unread order is fixed: saved-at descending → [7,4,3,2,1].
        try launchApp(articles: Fixtures.standardCorpus) { options in
            options.pinnedDefaults["sortField"] = "savedAt"
            options.pinnedDefaults["sortAscending"] = "0"
        }
        sidebar.select(.unread)
        XCTAssertTrue(list.waitForRowCount(5), "Unread starts with 5")

        // 1. Arrow-key down/up through the list; the reader follows each selection.
        list.open(Fixtures.Ids.swiftTips)
        assertReaderShows("Swift Tips", "reader opens the first selection")
        keyboard.arrowDown()
        assertReaderShows("Minimal", "↓ moves selection; reader follows")
        keyboard.arrowDown()
        assertReaderShows(unicodeTitle, "↓ again; reader follows")
        keyboard.arrowUp()
        assertReaderShows("Minimal", "↑ moves back; reader follows")

        // 2a. ⌘U marks the selected (minimal) read → it leaves Unread in one motion,
        //     selection advances to the unicode article, counts move, file gets read_at.
        keyboard.markRead()
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitDisappears(), "⌘U removes the read row")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 4), "Unread 5→4")
        XCTAssertTrue(sidebar.waitForCount(.read, equals: 4), "Read 3→4")
        assertReaderShows(unicodeTitle, "selection advanced after ⌘U")
        XCTAssertTrue(waitForFrontmatter(id: Fixtures.Ids.minimal) { $0.isRead }, "read on disk")

        // 2b. ⌘⇧F favorites the now-selected (unicode) → it STAYS in Unread (favoriting
        //     isn't a read-state change), Favorites 3→4, a heart appears, file favorited.
        keyboard.toggleFavorite()
        XCTAssertTrue(sidebar.waitForCount(.favorites, equals: 4), "Favorites 3→4")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 4), "still Unread 4 (favorite doesn't remove)")
        XCTAssertTrue(list.rowHasIndicator(Fixtures.Ids.unicode, label: "Favorite"), "heart on the row")
        XCTAssertTrue(waitForFrontmatter(id: Fixtures.Ids.unicode) { $0.favorite }, "favorite on disk")

        // 2c. ⌘⌫ archives the selected (unicode) → it leaves Unread in one motion,
        //     selection advances to the kitchen-sink article, counts move, file archived.
        keyboard.archive()
        XCTAssertTrue(list.row(Fixtures.Ids.unicode).waitDisappears(), "⌘⌫ removes the archived row")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 3), "Unread 4→3")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 3), "Archive 2→3")
        assertReaderShows(kitchenSinkTitle, "selection advanced after ⌘⌫")
        XCTAssertTrue(waitForFrontmatter(id: Fixtures.Ids.unicode) { $0.archived }, "archived on disk")

        // 3. ⌘K jumps focus to the search field; the typed term filters the list;
        //    Escape clears it and the list returns. Type with a verify/retry — the
        //    first synthesized keystroke into a freshly-focused field is dropped on
        //    this host — but never click, so this still proves ⌘K
        //    put focus there. "Tips" is unique to Swift Tips and carries no "c".
        //    Assert the filter via targeted rows, not a full row-count enumeration:
        //    the kitchen-sink article is open in the reader, and walking its many
        //    static texts while the list reloads races the accessibility snapshot.
        keyboard.focusSearch()
        typeIntoFocusedSearch("Tips")
        XCTAssertEqual(list.searchField.value as? String, "Tips", "⌘K focused search; typing landed there")
        XCTAssertTrue(list.row(Fixtures.Ids.swiftTips).waitExists(), "the match stays in the list")
        XCTAssertTrue(list.row(Fixtures.Ids.swift).waitDisappears(), "a non-match drops out")
        XCTAssertTrue(list.row(Fixtures.Ids.kitchenSink).waitDisappears(), "the other non-match drops out")
        keyboard.escape()
        XCTAssertTrue(list.row(Fixtures.Ids.swift).waitExists(), "Escape clears the search; the list returns")
        XCTAssertTrue(list.row(Fixtures.Ids.kitchenSink).waitExists(), "the cleared list shows the other rows")

        // 4. ⌘/ opens the keyboard-shortcuts cheat sheet; Escape dismisses it (its
        //    Done button is bound to `.cancelAction`). Closing by key fits the
        //    keyboard-only journey and avoids locating the button on macOS.
        keyboard.showShortcuts()
        XCTAssertTrue(shortcutsSheet.sheet.waitExists(), "⌘/ opens the shortcuts sheet")
        keyboard.escape()
        XCTAssertTrue(shortcutsSheet.sheet.waitDisappears(), "Escape closes the sheet")

        // 5. ⌃⌘S toggles the sidebar away for a focused layout, then back.
        let sidebarAll = app.byId(A11y.Sidebar.viewRow("all"))
        XCTAssertTrue(wait { sidebarAll.isHittable }, "sidebar visible before the toggle")
        keyboard.toggleSidebar()
        XCTAssertTrue(wait { !sidebarAll.isHittable }, "⌃⌘S hides the sidebar")
        keyboard.toggleSidebar()
        XCTAssertTrue(wait { sidebarAll.isHittable }, "⌃⌘S brings the sidebar back")

        // 6. ⌘⇧R enters focus mode — hiding BOTH the sidebar and the reading list so
        //    only the reader remains — then exits, restoring both. The open reading
        //    stays put throughout (focus mode reflows columns, never reloads the
        //    detail).
        let anyRow = list.row(Fixtures.Ids.swiftTips)
        let openReaderTitle = reader.titleText
        XCTAssertTrue(wait { anyRow.isHittable }, "reading list visible before focus")
        keyboard.toggleFocusMode()
        XCTAssertTrue(wait { !sidebarAll.isHittable }, "⌘⇧R hides the sidebar")
        XCTAssertTrue(wait { !anyRow.isHittable }, "⌘⇧R hides the reading list")
        XCTAssertEqual(reader.titleText, openReaderTitle, "the reader stays put in focus mode")
        keyboard.toggleFocusMode()
        XCTAssertTrue(wait { sidebarAll.isHittable }, "⌘⇧R restores the sidebar")
        XCTAssertTrue(wait { anyRow.isHittable }, "⌘⇧R restores the reading list")
    }

    /// Types `text` into the already-focused search field, retrying if a keystroke
    /// is dropped — the first character into a just-focused field is lost on this
    /// host. Deliberately never clicks the field, so the caller can
    /// prove ⌘K (not a click) put keyboard focus there.
    private func typeIntoFocusedSearch(_ text: String) {
        let field = list.searchField
        // Clear → type → verify, mirroring the proven `ReadingListPage.search`
        // retry: the first typed attempt into the just-focused field loses a
        // keystroke, the second (warmed-up) one lands whole.
        for _ in 0 ..< 3 {
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(.delete, modifierFlags: [])
            app.typeText(text)
            if (field.value as? String) == text {
                return
            }
        }
    }

    /// Polls until the reader header shows `title`, proving a selection change
    /// propagated to the detail column. Forwards `file`/`line` so a failure points
    /// at the call site, not this helper.
    private func assertReaderShows(
        _ title: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(wait { reader.titleText == title }, message, file: file, line: line)
    }
}
