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

    /// The badge count for a view, or 0 when the badge is absent (the app hides
    /// the badge at zero).
    func count(of view: SmartView) -> Int {
        let badge = app.byId(A11y.Sidebar.viewCount(view.rawValue))
        guard badge.exists else { return 0 }
        return Int(badge.label) ?? 0
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
        let badge = app.byId(A11y.Sidebar.tagCount(tag))
        guard badge.exists else { return 0 }
        return Int(badge.label) ?? 0
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
}
