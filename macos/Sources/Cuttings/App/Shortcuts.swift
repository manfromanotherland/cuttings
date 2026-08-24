// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A single keyboard shortcut: the binding applied with `.keyboardShortcut`, plus
/// a human-readable title and glyph for the shortcuts cheat sheet. This is the
/// single source of truth — the menu commands and the cheat sheet both read from
/// `ShortcutCatalog`, so the two can never drift apart.
struct AppShortcut: Identifiable {
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    /// Display glyph for the key itself (e.g. "T", "K", "⌫"). The modifier glyphs
    /// are derived from `modifiers`, so only the key needs spelling out here.
    let keyGlyph: String

    var id: String {
        title
    }

    /// macOS-style rendering, e.g. "⌘⇧T". Modifier order matches the menu bar:
    /// Control, Option, Shift, Command.
    var display: String {
        var glyphs = ""
        if modifiers.contains(.control) {
            glyphs += "⌃"
        }
        if modifiers.contains(.option) {
            glyphs += "⌥"
        }
        if modifiers.contains(.shift) {
            glyphs += "⇧"
        }
        if modifiers.contains(.command) {
            glyphs += "⌘"
        }
        return glyphs + keyGlyph
    }
}

extension View {
    /// Apply a catalog shortcut, so call sites stay in sync with the cheat sheet.
    func keyboardShortcut(_ shortcut: AppShortcut) -> some View {
        keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}

/// Every keyboard shortcut in the app, grouped for display. Adding or changing a
/// shortcut here updates both the menu binding and the cheat sheet at once.
enum ShortcutCatalog {
    struct Group: Identifiable {
        let name: String
        let shortcuts: [AppShortcut]
        var id: String {
            name
        }
    }

    // The catalog below lists one shortcut per row — title / key / modifiers /
    // glyph — so they read top-to-bottom like a table. The rows run long, so
    // line_length is off for this block only.
    // swiftlint:disable line_length

    // Article actions
    static let toggleRead = AppShortcut(title: "Mark Read / Unread", key: "u", modifiers: .command, keyGlyph: "U")
    static let toggleFavorite = AppShortcut(title: "Add / Remove Favorite", key: "f", modifiers: [.command, .shift], keyGlyph: "F")
    static let editTags = AppShortcut(title: "Edit Tags", key: "t", modifiers: [.command, .shift], keyGlyph: "T")
    static let toggleHighlights = AppShortcut(title: "Show / Hide Highlights", key: "h", modifiers: [.command, .shift], keyGlyph: "H")
    static let archive = AppShortcut(title: "Archive", key: .delete, modifiers: .command, keyGlyph: "⌫")
    static let delete = AppShortcut(title: "Delete", key: .delete, modifiers: [.command, .option], keyGlyph: "⌫")
    static let openInBrowser = AppShortcut(title: "Open in Browser", key: "o", modifiers: [.command, .shift], keyGlyph: "O")

    // View / navigation
    static let focusSearch = AppShortcut(title: "Focus Search", key: "k", modifiers: .command, keyGlyph: "K")
    static let toggleSidebar = AppShortcut(title: "Toggle Sidebar", key: "s", modifiers: [.control, .command], keyGlyph: "S")
    static let toggleFocusMode = AppShortcut(title: "Toggle Focus Mode", key: "r", modifiers: [.command, .shift], keyGlyph: "R")

    // Reading
    static let increaseFont = AppShortcut(title: "Increase Text Size", key: "+", modifiers: .command, keyGlyph: "+")
    static let decreaseFont = AppShortcut(title: "Decrease Text Size", key: "-", modifiers: .command, keyGlyph: "-")

    /// Help
    static let showShortcuts = AppShortcut(title: "Keyboard Shortcuts", key: "/", modifiers: .command, keyGlyph: "/")

    /// Groups in cheat-sheet display order.
    static let groups: [Group] = [
        Group(name: "Article", shortcuts: [toggleRead, toggleFavorite, editTags, toggleHighlights, archive, delete, openInBrowser]),
        Group(name: "View", shortcuts: [focusSearch, toggleSidebar, toggleFocusMode]),
        Group(name: "Reading", shortcuts: [increaseFont, decreaseFont]),
        Group(name: "Help", shortcuts: [showShortcuts])
    ]
    // swiftlint:enable line_length
}
