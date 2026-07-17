// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import AppKit
import Observation

// The behavior lives in sibling extension files in this folder, one per
// concern: Library.swift (onboarding, boot, sync), Readings.swift (list
// loading, search, sidebar reloads), Mutations.swift (row edits with
// optimistic UI), and Highlights.swift. This file holds the stored state,
// `init`, and the AppKit focus helpers.
@MainActor
@Observable
final class AppState {
    private enum SortDefaultsKey {
        static let field = "sortField"
        static let ascending = "sortAscending"
    }
    // ── Navigation state ──────────────────────────────────────────────────
    var libraryURL: URL?

    /// True from launch until the first boot from a persisted bookmark settles.
    /// `libraryURL` is only set at the end of the async `boot`, so without this
    /// flag the brief gap between launch and boot would flash the onboarding
    /// screen even when a saved library exists. Onboarding keys off both:
    /// show it only when there's no library *and* we aren't restoring one.
    var isRestoringLibrary: Bool = false
    var readings: [FfiReadingRow] = []
    var selectedId: String?
    var searchQuery: String = ""

    /// Sort applied while a search is active. Kept separate from `sortField` so
    /// searching (which defaults to relevance) never clobbers the list's own
    /// persisted sort. Not persisted — a fresh search starts on relevance.
    var searchSort: ReadingSort = .relevance

    /// Pending debounced search reload. Each keystroke cancels the previous one
    /// so the core is queried once typing settles, not per character. Plumbing
    /// only — not part of the observable UI state.
    @ObservationIgnored var searchTask: Task<Void, Never>?

    var sidebarSelection: SidebarSelection? = .view(.all)

    /// Sort field for the reading list, persisted across launches. The default
    /// here only initializes the backing store; `init` immediately overwrites it
    /// with the persisted preference (re-persisting the same value harmlessly).
    var sortField: ReadingSort = .savedAt {
        didSet {
            AppDefaults.store.set(sortField.rawValue, forKey: SortDefaultsKey.field)
        }
    }

    /// Sort direction (ascending when `true`), persisted across launches.
    /// Descending is the default for every field.
    var sortAscending: Bool = false {
        didSet {
            AppDefaults.store.set(sortAscending, forKey: SortDefaultsKey.ascending)
        }
    }

    /// Reading awaiting delete confirmation, if any. Drives the confirm dialog.
    var pendingDelete: FfiReadingRow?

    /// Drives the tag-picker sheet for the open reading. Held here (rather than in
    /// the detail view) so both the toolbar button and the ⌘⇧T menu command can
    /// open it.
    var showTagSheet: Bool = false

    /// Drives the highlights inspector for the open reading. Held here so both the
    /// toolbar button and the ⌘⇧H menu command can toggle it.
    var showHighlights: Bool = false

    /// Drives the keyboard-shortcuts cheat sheet (the ⌘/ command).
    var showShortcuts: Bool = false

    /// Highlights for the currently open reading. Drives both the reader's
    /// in-text tinting and the highlights inspector.
    var highlights: [FfiHighlight] = []

    /// Currently active smart view (derived from `sidebarSelection`).
    var activeView: SidebarItem {
        if case .view(let item) = sidebarSelection { return item }
        return .all
    }

    /// Currently selected tag filter, if any (derived from `sidebarSelection`).
    var selectedTag: String? {
        if case .tag(let tag) = sidebarSelection { return tag }
        return nil
    }

    /// Currently selected rating filter (1–5), if any.
    var selectedRating: UInt8? {
        if case .rating(let rating) = sidebarSelection { return rating }
        return nil
    }

    // ── Sidebar metadata ──────────────────────────────────────────────────

    /// Sidebar badge numbers (view counts, tag counts, rating counts) with
    /// their optimistic delta bookkeeping; reconciled by `loadSidebar()`.
    var sidebar = SidebarCounts()

    // ── Status ────────────────────────────────────────────────────────────
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var hasMoreReadings: Bool = false
    var error: String?

    /// True while the user is editing a text field (the toolbar search field, the
    /// tag picker, …). macOS dispatches menu/context-menu key-equivalents *before*
    /// the focused field editor, so a global ⌘⌫ ("Archive") would fire mid-edit
    /// instead of deleting the line. Commands whose shortcuts collide with the
    /// field editor's own keys disable themselves while this holds, letting the
    /// keystroke fall through to standard text editing. Kept in sync by
    /// `editingMonitor` (see `TextEditingMonitor`).
    var isEditingText: Bool = false
    var isFocusMode: Bool = false

    // Internal rather than private so the sibling extension files in this
    // folder can reach them — Swift's `private` is file-scoped.
    let pageSize: UInt32 = 100
    var core: CoreBridge?
    var accessedURL: URL?
    var watcher: LibraryWatcher?

    private var editingMonitor: TextEditingMonitor?

    init() {
        // Restore the persisted sort preference (defaults: saved-at, descending).
        let defaults = AppDefaults.store
        sortField = defaults.string(forKey: SortDefaultsKey.field)
            .flatMap(ReadingSort.init(rawValue:)) ?? .savedAt
        sortAscending = defaults.bool(forKey: SortDefaultsKey.ascending)

        if TestHooks.isUITesting {
            // UI-testing: never resolve the persisted bookmark (leave the dev's
            // real library untouched). Boot the pinned temp library if one was
            // given; otherwise fall through to the onboarding screen.
            if let path = TestHooks.libraryPath {
                isRestoringLibrary = true
                Task { await boot(url: URL(fileURLWithPath: path)) }
            }
        } else if let url = LibraryBookmark.resolve() {
            accessedURL = url
            isRestoringLibrary = true
            Task { await boot(url: url) }
        }

        editingMonitor = TextEditingMonitor { [weak self] editing in
            self?.isEditingText = editing
        }
    }

    // ── Search focus ──────────────────────────────────────────────────────────

    /// Move keyboard focus to the toolbar search field (the ⌘K command). SwiftUI's
    /// `.searchable` exposes no focus binding we can drive from a menu command, so
    /// we reach the field through AppKit: prefer the toolbar's search item, and
    /// fall back to finding the `NSSearchField` in the window's view tree.
    func focusSearchField() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        if let item = window.toolbar?.items
            .compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return
        }
        if let field = window.contentView.flatMap(Self.firstSearchField(in:)) {
            window.makeFirstResponder(field)
        }
    }

    private static func firstSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = firstSearchField(in: subview) { return field }
        }
        return nil
    }
}
