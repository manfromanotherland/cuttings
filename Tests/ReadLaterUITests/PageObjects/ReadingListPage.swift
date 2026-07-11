// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The middle column: the reading list, its rows, sort menu, search, and empty
/// states.
struct ReadingListPage {
    let app: XCUIApplication

    /// Sort menu labels, mirroring `ReadingSort.label` / `directionLabel`.
    enum Sort {
        static let dateSaved = "Date saved"
        static let dateRead = "Date read"
        static let rating = "Rating"
        static let timeToRead = "Time to read"
        static let relevance = "Relevance"

        static let newestFirst = "Newest first"
        static let oldestFirst = "Oldest first"
        static let readMostRecently = "Read most recently"
        static let readLeastRecently = "Read least recently"
        static let highestRated = "Highest rated"
        static let lowestRated = "Lowest rated"
        static let longestFirst = "Longest first"
        static let shortestFirst = "Shortest first"
    }

    var table: XCUIElement { app.byId(A11y.List.table) }

    // ── Rows ────────────────────────────────────────────────────────────────

    func row(_ id: String) -> XCUIElement { app.byId(A11y.List.row(id)) }

    /// Selecting a row also opens it in the reader (selection drives the detail).
    func select(_ id: String) { row(id).clickWhenReady() }
    func open(_ id: String) { select(id) }

    /// The ids of the currently loaded rows, in list order — for sort-oracle and
    /// membership assertions. A row's id can appear on several static texts, so
    /// dedupe while preserving first-seen (top-to-bottom) order.
    var orderedRowIds: [String] {
        let prefix = A11y.List.row("")
        var seen = Set<String>()
        var result: [String] = []
        for element in app.allByIdPrefix(prefix) {
            let id = String(element.identifier.dropFirst(prefix.count))
            if !id.isEmpty, seen.insert(id).inserted { result.append(id) }
        }
        return result
    }

    /// Polls until the number of loaded rows equals `expected` — for asserting a
    /// search narrowed the list (search is debounced and applied asynchronously).
    @discardableResult
    func waitForRowCount(_ expected: Int, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if orderedRowIds.count == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    /// Whether row `id` contains a static text matching `text` (title, site, …).
    func row(_ id: String, contains text: String) -> Bool {
        row(id)
            .descendants(matching: .staticText)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
            .exists
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
    func scrollDown() { table.swipeUp() }

    /// Scroll until row `id` exists (or the timeout elapses).
    @discardableResult
    func scrollToRow(_ id: String, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !row(id).exists {
            if Date() >= deadline { return false }
            scrollDown()
        }
        return true
    }

    // ── Search ────────────────────────────────────────────────────────────
    // The `.searchable` field is a system NSSearchField (no custom identifier),
    // so it's reached through the search-field element type.

    var searchField: XCUIElement { app.searchFields.firstMatch }

    func search(_ text: String) {
        let field = searchField
        field.clickWhenReady()
        field.typeText(text)
    }

    func clearSearch() {
        let field = searchField
        field.clickWhenReady()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
    }

    // ── Sort ──────────────────────────────────────────────────────────────

    func openSortMenu() { app.byId(A11y.List.sortMenu).clickWhenReady() }

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

    var emptyState: XCUIElement { app.byId(A11y.List.emptyState) }
    var searchEmptyState: XCUIElement { app.byId(A11y.List.searchEmptyState) }
    var tagEmptyState: XCUIElement { app.byId(A11y.List.tagEmptyState) }
    var clearTagFilterButton: XCUIElement { app.byId(A11y.List.clearTagFilter) }

    func clearTagFilter() { clearTagFilterButton.clickWhenReady() }

    // ── Delete confirmation ───────────────────────────────────────────────

    func confirmDelete() { app.tapDialogButton("Delete") }
    func cancelDelete() { app.tapDialogButton("Cancel") }
}
