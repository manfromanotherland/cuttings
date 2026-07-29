// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Stable accessibility identifiers shared by the app and the XCUITest suite, so
/// tests locate controls by identifier rather than by (localizable, ambiguous)
/// on-screen wording.
///
/// This file is compiled into **both** the `ReadControl` app target and the
/// `ReadControlUITests` target (it lives under `Sources/ReadControl/`, and the test
/// target lists it explicitly) so the two sides agree on one source of truth.
///
/// **Dependency-free by design:** the UI-test target can't see app types, so the
/// parameterized helpers take primitives (`String`/`Int`/`UInt8`). The app passes
/// `item.id` / `mode.id` / a reading id at the call site; a test passes the same
/// literal (e.g. `A11y.Sidebar.viewRow("unread")`).
enum A11y {
    /// ── Onboarding ────────────────────────────────────────────────────────
    enum Onboarding {
        static let title = "onboarding.title"
        static let chooseLibrary = "onboarding.chooseLibrary"
    }

    /// ── Sidebar ─────────────────────────────────────────────────────────────
    enum Sidebar {
        /// A smart-view row (All/Unread/Read/Archive/Favorites), keyed by `SidebarItem.id`.
        static func viewRow(_ item: String) -> String {
            "sidebar.view.\(item)"
        }

        /// The count badge on a smart-view row.
        static func viewCount(_ item: String) -> String {
            "sidebar.view.\(item).count"
        }

        /// A tag pill in the Tags section, keyed by tag name.
        static func tagTile(_ tag: String) -> String {
            "sidebar.tag.\(tag)"
        }

        /// The count badge on a tag pill.
        static func tagCount(_ tag: String) -> String {
            "sidebar.tag.\(tag).count"
        }

        /// A rating row in the Ratings section (1–5); its label carries the count.
        static func ratingRow(_ rating: UInt8) -> String {
            "sidebar.rating.\(rating)"
        }

        static let settingsButton = "sidebar.settings"
        /// A theme button in the appearance popover, keyed by `AppearanceMode.id`.
        static func themeButton(_ mode: String) -> String {
            "sidebar.appearance.theme.\(mode)"
        }

        static let fontPicker = "sidebar.appearance.font"
        static let fontSizeSlider = "sidebar.appearance.fontSize"
    }

    /// ── Reading list ──────────────────────────────────────────────────────
    enum List {
        static let table = "list.table"
        /// A reading row, keyed by reading id.
        static func row(_ id: String) -> String {
            "list.row.\(id)"
        }

        /// A hidden probe describing the loaded rows: its accessibility **label**
        /// is the row count and its **value** is the ordered row ids (comma-
        /// joined). The suite reads both from one `firstMatch` instead of
        /// enumerating rows, which trips an XCUITest snapshot bug on article
        /// headings (`AXHeading`).
        static let rows = "list.rows"
        static let sortMenu = "list.sort"
        /// Default "Nothing here yet" empty state.
        static let emptyState = "list.empty"
        /// Search "No results" empty state.
        static let searchEmptyState = "list.empty.search"
        /// Tag-filter empty state (offers Clear tag filter).
        static let tagEmptyState = "list.empty.tag"
        static let clearTagFilter = "list.clearTagFilter"
    }

    /// ── Reader / detail ─────────────────────────────────────────────────────
    enum Detail {
        static let title = "detail.title"
        static let tags = "detail.tags"
        static let empty = "detail.empty"
        static let oversize = "detail.oversize"
        static let oversizeOpenInBrowser = "detail.oversize.openInBrowser"
    }

    /// ── Reader content ────────────────────────────────────────────────────────
    enum Reader {
        /// A tappable article image (figure). Shared by every figure in the
        /// reader, so tests match the first one.
        static let figure = "reader.figure"
    }

    /// ── Image zoom lightbox ───────────────────────────────────────────────────
    enum Lightbox {
        static let image = "lightbox.image"
        static let close = "lightbox.close"
    }

    /// ── Reader toolbar (7 actions; archive/unarchive share the slot) ──────────
    enum Toolbar {
        static let markRead = "toolbar.markRead"
        static let favorite = "toolbar.favorite"
        static let archive = "toolbar.archive"
        static let unarchive = "toolbar.unarchive"
        static let openInBrowser = "toolbar.openInBrowser"
        static let tags = "toolbar.tags"
        static let highlight = "toolbar.highlight"
        /// The "select some text first" popover raised by `highlight`.
        static let highlightHint = "toolbar.highlightHint"
        static let delete = "toolbar.delete"
    }

    /// ── Rating footer ─────────────────────────────────────────────────────
    enum RatingFooter {
        /// A star button (1–5).
        static func star(_ index: Int) -> String {
            "rating.star.\(index)"
        }
    }

    /// ── Tag picker sheet ────────────────────────────────────────────────────
    enum TagPicker {
        static let searchField = "tagPicker.search"
        static let addRow = "tagPicker.add"
        /// Inline message shown when the typed name exceeds the tag-length limit.
        static let lengthError = "tagPicker.lengthError"
        /// An existing-tag toggle row, keyed by tag name.
        static func row(_ tag: String) -> String {
            "tagPicker.row.\(tag)"
        }

        static let done = "tagPicker.done"
    }

    /// ── Highlights inspector ────────────────────────────────────────────────
    enum Highlights {
        static let list = "highlights.list"
        /// A highlight row, keyed by highlight id.
        static func row(_ id: String) -> String {
            "highlights.row.\(id)"
        }

        static let emptyState = "highlights.empty"
    }

    /// ── Shortcuts sheet ─────────────────────────────────────────────────────
    enum Shortcuts {
        static let sheet = "shortcuts.sheet"
        static let done = "shortcuts.done"
    }

    /// ── Settings window ─────────────────────────────────────────────────────
    enum Settings {
        static let appearanceTab = "settings.tab.appearance"
        static let typographyTab = "settings.tab.typography"
        static let libraryTab = "settings.tab.library"
        static let extensionsTab = "settings.tab.extensions"
        static let themePicker = "settings.theme"
        static let fontPicker = "settings.font"
        static let sizePicker = "settings.size"
        static let changeLibrary = "settings.changeLibrary"
        static let reinstallManifest = "settings.reinstallManifest"
    }
}
