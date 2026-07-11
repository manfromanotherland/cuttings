// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The five smart views, mirroring the app's `SidebarItem` ids so the page
/// object stays dependency-free.
enum SmartView: String {
    case all, unread, read, archive, favorites
}

/// The left column: smart views + counts, tag tiles + counts, rating rows, and
/// the appearance popover behind the settings gear.
struct SidebarPage {
    let app: XCUIApplication

    // ── Smart views ───────────────────────────────────────────────────────

    func select(_ view: SmartView) {
        app.byId(A11y.Sidebar.viewRow(view.rawValue)).clickWhenReady()
    }

    /// The count for a view. The sidebar List collapses each row into a single
    /// element, so the count is read from the row's accessibility value (set by
    /// the app), with label/badge fallbacks.
    func count(of view: SmartView) -> Int {
        Self.count(
            row: app.byId(A11y.Sidebar.viewRow(view.rawValue)),
            badge: app.byId(A11y.Sidebar.viewCount(view.rawValue))
        )
    }

    /// Polls until a view's count equals `expected` (counts load asynchronously
    /// after launch and after mutations).
    @discardableResult
    func waitForCount(_ view: SmartView, equals expected: Int, timeout: TimeInterval = 8) -> Bool {
        poll(timeout: timeout) { count(of: view) == expected }
    }

    // ── Tags ────────────────────────────────────────────────────────────────

    func selectTag(_ tag: String) {
        app.byId(A11y.Sidebar.tagTile(tag)).clickWhenReady()
    }

    func tagTile(_ tag: String) -> XCUIElement { app.byId(A11y.Sidebar.tagTile(tag)) }

    func tagCount(_ tag: String) -> Int {
        Self.count(
            row: app.byId(A11y.Sidebar.tagTile(tag)),
            badge: app.byId(A11y.Sidebar.tagCount(tag))
        )
    }

    @discardableResult
    func waitForTagCount(_ tag: String, equals expected: Int, timeout: TimeInterval = 8) -> Bool {
        poll(timeout: timeout) { tagCount(tag) == expected }
    }

    // ── Ratings ───────────────────────────────────────────────────────────

    func selectRating(_ rating: UInt8) {
        app.byId(A11y.Sidebar.ratingRow(rating)).clickWhenReady()
    }

    func ratingRow(_ rating: UInt8) -> XCUIElement { app.byId(A11y.Sidebar.ratingRow(rating)) }

    // ── Appearance popover ────────────────────────────────────────────────

    func openAppearancePopover() {
        app.byId(A11y.Sidebar.settingsButton).clickWhenReady()
    }

    /// Set the theme from the appearance popover (`mode` mirrors `AppearanceMode.id`:
    /// `light` / `dark` / `system`). Opens the popover first.
    func setTheme(_ mode: String) {
        openAppearancePopover()
        app.byId(A11y.Sidebar.themeButton(mode)).clickWhenReady()
    }

    var fontPicker: XCUIElement { app.byId(A11y.Sidebar.fontPicker) }
    var fontSizeSlider: XCUIElement { app.byId(A11y.Sidebar.fontSizeSlider) }

    // ── Helpers ───────────────────────────────────────────────────────────

    private func poll(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    /// Reads a count for a collapsed sidebar row: prefer the row's accessibility
    /// value (set by the app), then a trailing number in its label, then a
    /// separately-queryable badge if one exists. Absent row ⇒ 0.
    private static func count(row: XCUIElement, badge: XCUIElement) -> Int {
        guard row.exists else {
            return badge.exists ? (Int(badge.label) ?? 0) : 0
        }
        if let value = row.value as? String, let number = lastNumber(in: value) { return number }
        if let number = lastNumber(in: row.label) { return number }
        return badge.exists ? (Int(badge.label) ?? 0) : 0
    }

    /// The last run of digits in `text` (the count always sits at the end of a
    /// row's label/value, after the view or tag name).
    private static func lastNumber(in text: String) -> Int? {
        var last: Int?
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                last = Int(current)
                current = ""
            }
        }
        if !current.isEmpty { last = Int(current) }
        return last
    }
}
