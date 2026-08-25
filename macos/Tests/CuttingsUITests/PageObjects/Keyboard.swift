// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Drives the app's keyboard shortcuts, mirroring `ShortcutCatalog`. Keeping them
/// in one place means a journey reads as `keyboard.toggleFavorite()` rather than a raw
/// `typeKey`, and a shortcut change is updated once.
struct Keyboard {
    let app: XCUIApplication

    /// ── Article actions (act on the current selection) ────────────────────
    func toggleFavorite() {
        app.typeKey("f", modifierFlags: [.command, .shift])
    } // ⌘⇧F
    func editTags() {
        app.typeKey("t", modifierFlags: [.command, .shift])
    } // ⌘⇧T
    func toggleHighlights() {
        app.typeKey("h", modifierFlags: [.command, .shift])
    } // ⌘⇧H
    func delete() {
        app.typeKey(.delete, modifierFlags: [.command, .option])
    } // ⌘⌥⌫
    func openInBrowser() {
        app.typeKey("o", modifierFlags: [.command, .shift])
    } // ⌘⇧O

    /// ── View / navigation ─────────────────────────────────────────────────
    func focusSearch() {
        app.typeKey("k", modifierFlags: .command)
    } // ⌘K
    func toggleFocusMode() {
        app.typeKey("r", modifierFlags: [.command, .shift])
    } // ⌘⇧R

    func previousItem() {
        app.typeKey("k", modifierFlags: [])
    } // K

    func nextItem() {
        app.typeKey("j", modifierFlags: [])
    } // J

    func arrowLeft() {
        app.typeKey(.leftArrow, modifierFlags: [])
    }

    func arrowRight() {
        app.typeKey(.rightArrow, modifierFlags: [])
    }

    /// ── Reading ────────────────────────────────────────────────────────────
    func increaseFontSize() {
        app.typeKey("+", modifierFlags: .command)
    } // ⌘+
    func decreaseFontSize() {
        app.typeKey("-", modifierFlags: .command)
    } // ⌘-

    /// ── Help ──────────────────────────────────────────────────────────────
    func showShortcuts() {
        app.typeKey("/", modifierFlags: .command)
    } // ⌘/

    /// ── List navigation ─────────────────────────────────────────────────────
    func arrowDown() {
        app.typeKey(.downArrow, modifierFlags: [])
    }

    func arrowUp() {
        app.typeKey(.upArrow, modifierFlags: [])
    }

    /// Escape — clears search / dismisses.
    func escape() {
        app.typeKey(.escape, modifierFlags: [])
    }
}
