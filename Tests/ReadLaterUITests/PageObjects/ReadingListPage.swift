// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import AppKit

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
            .contains { ((($0.value as? String) ?? "").localizedCaseInsensitiveContains(text)) }
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

    /// Clears the field and types `text`, verifying the field's value and retrying
    /// once. Search is debounced with a live list reload, so a keystroke can be
    /// dropped if a reload fires mid-type — keep search terms short, and the
    /// verify/retry covers an occasional miss.
    func search(_ text: String) {
        let field = searchField
        field.clickWhenReady()
        for _ in 0..<2 {
            clearField(field)
            field.typeText(text)
            if (field.value as? String) == text { return }
        }
    }

    func clearSearch() {
        let field = searchField
        field.clickWhenReady()
        clearField(field)
    }

    /// Enters `text` into the search field via the pasteboard (⌘V) rather than
    /// synthetic keystrokes: this host drops the letter "c" and the first keystroke
    /// from `typeText` (see E2E-16), and a single paste sidesteps both — while also
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

    /// The sort menu button. Only present when the list has rows — it's hidden
    /// for every empty state (see `ReadingListView.toolbarItems`).
    var sortMenu: XCUIElement { app.byId(A11y.List.sortMenu) }

    func openSortMenu() { sortMenu.clickWhenReady() }

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

    /// The "Clear tag filter" action in the tag-empty state. `ContentUnavailableView`
    /// surfaces the outer view's `accessibilityIdentifier` but not its action
    /// button's on macOS, so the id match usually misses — fall back to the button
    /// by title (the `tagEmptyState` id already anchors that we're in the right state).
    var clearTagFilterButton: XCUIElement {
        let identified = app.byId(A11y.List.clearTagFilter)
        return identified.exists ? identified : app.buttons["Clear tag filter"]
    }

    func clearTagFilter() { clearTagFilterButton.clickWhenReady() }

    // ── Delete confirmation ───────────────────────────────────────────────

    func confirmDelete() { app.tapDialogButton("Delete") }
    func cancelDelete() { app.tapDialogButton("Cancel") }
}
