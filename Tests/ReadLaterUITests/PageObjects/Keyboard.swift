// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Drives the app's keyboard shortcuts, mirroring `ShortcutCatalog`. Keeping them
/// in one place means a journey reads as `keyboard.markRead()` rather than a raw
/// `typeKey`, and a shortcut change is updated once.
struct Keyboard {
    let app: XCUIApplication

    // ── Article actions (act on the current selection) ────────────────────
    func markRead() { app.typeKey("u", modifierFlags: .command) }              // ⌘U
    func toggleFavorite() { app.typeKey("f", modifierFlags: [.command, .shift]) } // ⌘⇧F
    func editTags() { app.typeKey("t", modifierFlags: [.command, .shift]) }    // ⌘⇧T
    func toggleHighlights() { app.typeKey("h", modifierFlags: [.command, .shift]) } // ⌘⇧H
    func archive() { app.typeKey(.delete, modifierFlags: .command) }           // ⌘⌫
    func delete() { app.typeKey(.delete, modifierFlags: [.command, .option]) } // ⌘⌥⌫
    func openInBrowser() { app.typeKey("o", modifierFlags: [.command, .shift]) } // ⌘⇧O

    // ── View / navigation ─────────────────────────────────────────────────
    func focusSearch() { app.typeKey("k", modifierFlags: .command) }           // ⌘K
    func toggleSidebar() { app.typeKey("s", modifierFlags: [.command, .control]) } // ⌃⌘S

    // ── Reading ────────────────────────────────────────────────────────────
    func increaseFontSize() { app.typeKey("+", modifierFlags: .command) }      // ⌘+
    func decreaseFontSize() { app.typeKey("-", modifierFlags: .command) }      // ⌘-

    // ── Help ──────────────────────────────────────────────────────────────
    func showShortcuts() { app.typeKey("/", modifierFlags: .command) }         // ⌘/

    // ── List navigation ─────────────────────────────────────────────────────
    func arrowDown() { app.typeKey(.downArrow, modifierFlags: []) }
    func arrowUp() { app.typeKey(.upArrow, modifierFlags: []) }

    /// Escape — clears search / dismisses.
    func escape() { app.typeKey(.escape, modifierFlags: []) }
}
