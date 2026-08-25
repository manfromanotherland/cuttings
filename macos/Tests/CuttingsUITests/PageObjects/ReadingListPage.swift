// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest

/// The visual board, its cards, toolbar controls, search, sort, and empty states.
struct ReadingListPage {
    let app: XCUIApplication

    /// Sort menu labels, mirroring `ReadingSort.label` / `directionLabel`.
    enum Sort {
        static let dateSaved = "Date saved"
        static let length = "Length"
        static let relevance = "Relevance"

        static let newestFirst = "Newest first"
        static let oldestFirst = "Oldest first"
        static let longestFirst = "Longest first"
        static let shortestFirst = "Shortest first"
    }

    var table: XCUIElement {
        app.byId(A11y.List.table)
    }

    var favoritesToggle: XCUIElement {
        app.byId(A11y.Filter.favorites)
    }

    var filterMenu: XCUIElement {
        app.byId(A11y.Filter.menu)
    }

    func showFavorites() {
        favoritesToggle.clickWhenReady()
    }

    func showAll() {
        favoritesToggle.clickWhenReady()
    }

    func selectTagFilter(_ tag: String) {
        filterMenu.clickWhenReady()
        let identified = app.byId(A11y.Filter.tag(tag))
        if identified.exists {
            identified.clickWhenReady()
        } else {
            app.menuItems["#\(tag)"].clickWhenReady()
        }
    }

    // ── Rows ────────────────────────────────────────────────────────────────

    func row(_ id: String) -> XCUIElement {
        app.byId(A11y.List.row(id))
    }

    /// Selecting a card opens it in the reading overlay.
    func select(_ id: String) {
        // Stay away from the trailing hover menu. SwiftUI can expose the
        // combined card as either a Button or MenuButton depending on hover.
        row(id).clickWhenReady(at: CGVector(dx: 0.25, dy: 0.5))
    }

    func open(_ id: String) {
        select(id)
    }

    /// The ids of the currently loaded rows, in list order — for sort-oracle and
    /// membership assertions.
    ///
    /// Read from the list's hidden probe (`A11y.List.rows`) via a single
    /// `firstMatch`, not by enumerating the row elements: an app-wide static-text
    /// enumeration trips an XCUITest snapshot bug that fails on the reader's
    /// article headings (`AXHeading`). Reading one element's value is the same path
    /// the sidebar counts use, which resolves fine through that bug.
    var orderedRowIds: [String] {
        guard let value = app.byId(A11y.List.rows).value as? String, !value.isEmpty else {
            return []
        }
        return value.split(separator: ",").map(String.init)
    }

    /// Polls until the number of loaded rows equals `expected` — for asserting a
    /// search narrowed the list (search is debounced and applied asynchronously).
    /// Reads the count from the same hidden probe (`A11y.List.rows`, count in its
    /// label) via a single `firstMatch`, for the reason above.
    @discardableResult
    func waitForRowCount(_ expected: Int, timeout: TimeInterval = 8) -> Bool {
        let probe = app.byId(A11y.List.rows)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if probe.exists, Int(probe.label) == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    /// Whether row `id` shows `text`. Each field in a row (title, site, reading
    /// time, excerpt) is a separate static text carrying the row's identifier,
    /// with the text in its **`.value`** (not `.label`), so match on any static
    /// text tagged with the row id whose value contains it. Reads the property
    /// directly — `CONTAINS` predicates don't match these SwiftUI elements.
    func row(_ id: String, contains text: String) -> Bool {
        // Narrow to this row's static texts server-side (matching(identifier:) is
        // reliable and cheap) before materializing — scanning every static text
        // in the app is what makes these tests slow.
        app.staticTexts.matching(identifier: A11y.List.row(id))
            .allElementsBoundByIndex
            .contains { (($0.value as? String) ?? "").localizedCaseInsensitiveContains(text) }
    }

    /// Whether row `id` shows the indicator glyph named `label`. The glyphs carry
    /// the row id in their identifier and the indicator name in their label, but
    /// their element type varies — the unread dot is a `Circle` (`Other`), the
    /// favorite heart is an SF Symbol (`Image`) — so check both.
    func rowHasIndicator(_ id: String, label: String) -> Bool {
        let identifier = A11y.List.row(id)
        func hasMatch(in query: XCUIElementQuery) -> Bool {
            query.matching(identifier: identifier)
                .allElementsBoundByIndex
                .contains { $0.label == label }
        }
        return hasMatch(in: app.otherElements) || hasMatch(in: app.images)
    }

    // ── Context menu ────────────────────────────────────────────────────────

    /// Right-click a row and click a menu item by title (context-menu items are
    /// addressed by their menu-item title, not an identifier).
    func invokeContextMenu(on id: String, item title: String) {
        row(id).rightClick()
        app.menuItems[title].clickWhenReady()
    }

    // ── Scrolling ───────────────────────────────────────────────────────────

    /// Scroll the list down (loads the next page for large corpora).
    func scrollDown() {
        table.swipeUp()
    }

    /// Scroll until row `id` exists (or the timeout elapses).
    @discardableResult
    func scrollToRow(_ id: String, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !row(id).exists {
            if Date() >= deadline {
                return false
            }
            scrollDown()
        }
        return true
    }

    // ── Search ────────────────────────────────────────────────────────────
    // The search box is a plain NSSearchField embedded at the top of the list
    // column (no custom identifier), so it's reached through the search-field
    // element type.

    var searchField: XCUIElement {
        app.searchFields.firstMatch
    }

    /// Clears the field and types `text`, verifying the field's value and retrying
    /// once. Search is debounced with a live list reload, so a keystroke can be
    /// dropped if a reload fires mid-type — keep search terms short, and the
    /// verify/retry covers an occasional miss.
    func search(_ text: String) {
        let field = searchField
        field.clickWhenReady()
        for _ in 0 ..< 2 {
            clearField(field)
            field.typeText(text)
            if (field.value as? String) == text {
                return
            }
        }
    }

    func clearSearch() {
        let field = searchField
        field.clickWhenReady()
        clearField(field)
    }

    /// Enters `text` into the search field via the pasteboard (⌘V) rather than
    /// synthetic keystrokes: this host drops the letter "c" and the first keystroke
    /// from `typeText`, and a single paste sidesteps both — while also
    /// landing atomically, past the search debounce.
    func pasteSearch(_ text: String) {
        let field = searchField
        field.clickWhenReady()
        clearField(field)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        field.typeKey("v", modifierFlags: .command)
    }

    private func clearField(_ field: XCUIElement) {
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
    }

    // ── Sort ──────────────────────────────────────────────────────────────

    /// The native toolbar's sort menu button.
    var sortMenu: XCUIElement {
        app.byId(A11y.List.sortMenu)
    }

    func openSortMenu() {
        sortMenu.clickWhenReady()
    }

    /// Pick a sort field (see `Sort`). Opens the menu, clicks the field, and the
    /// menu closes.
    func selectSortField(_ label: String) {
        openSortMenu()
        app.menuItems[label].clickWhenReady()
    }

    /// Pick a sort direction (see `Sort`). The order picker lives in the same menu.
    func selectSortDirection(_ label: String) {
        openSortMenu()
        app.menuItems[label].clickWhenReady()
    }

    // ── Empty states ────────────────────────────────────────────────────────

    var emptyState: XCUIElement {
        app.byId(A11y.List.emptyState)
    }

    var searchEmptyState: XCUIElement {
        app.byId(A11y.List.searchEmptyState)
    }

    var tagEmptyState: XCUIElement {
        app.byId(A11y.List.tagEmptyState)
    }

    /// The "Clear tag filter" action in the tag-empty state. `ContentUnavailableView`
    /// surfaces the outer view's `accessibilityIdentifier` but not its action
    /// button's on macOS, so the id match usually misses — fall back to the button
    /// by title (the `tagEmptyState` id already anchors that we're in the right state).
    var clearTagFilterButton: XCUIElement {
        let identified = app.byId(A11y.List.clearTagFilter)
        return identified.exists ? identified : app.buttons["Clear tag filter"]
    }

    func clearTagFilter() {
        clearTagFilterButton.clickWhenReady()
    }

    // ── Delete confirmation ───────────────────────────────────────────────

    func confirmDelete() {
        app.tapDialogButton("Delete")
    }

    func cancelDelete() {
        app.tapDialogButton("Cancel")
    }
}
