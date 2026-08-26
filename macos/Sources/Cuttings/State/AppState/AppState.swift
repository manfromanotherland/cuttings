// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Observation
import SwiftUI

// The behavior lives in sibling extension files in this folder, one per
// concern: Library.swift (onboarding, boot, sync), Readings.swift (list
// loading, search, filter reloads), Mutations.swift (row edits with
// optimistic UI) and Highlights.swift. This file holds the stored state,
// `init`, and the AppKit focus helpers.
@MainActor
@Observable
final class AppState {
    /// Keys the current board scope and search box persist under, plus retired
    /// kind/tag keys that are cleared during migration.
    private enum FilterDefaultsKey {
        static let kind = "selectedKind"
        static let scope = "activeScope"
        static let tag = "selectedTag"
        static let search = "searchQuery"
        static let legacyView = "activeView"
        static let legacyRating = "selectedRating"
    }

    private enum ExtensionSetupKey {
        /// The step is owed but not yet dismissed — persisted so quitting mid-step
        /// resumes on it.
        static let pending = "extensionSetupPending"
        /// The user has dismissed the step for good — persisted so it never shows
        /// again, including when they later re-pick a library from Settings.
        static let completed = "extensionSetupCompleted"
    }

    /// ── Navigation state ──────────────────────────────────────────────────
    var libraryURL: URL?

    /// True from launch until the first boot from a persisted bookmark settles.
    /// The restored URL is published immediately so the normal window shell and
    /// toolbar can render while the core hydrates; this flag keeps the board
    /// itself neutral and prevents onboarding from flashing if restoration fails
    /// before that first frame.
    var isRestoringLibrary: Bool = false

    /// Whether the extension-install step should show ahead of the main view (see
    /// `ContentView`). Raised on a fresh library pick (`pickLibrary`) and cleared
    /// only when the user taps "Continue" — never by boot — so quitting mid-step
    /// and relaunching resumes on the step instead of dropping into the library.
    ///
    /// Persisted so the step survives a relaunch; `init` restores it. Only the
    /// fresh-pick path raises it, so a library set up before this step existed (or
    /// one already dismissed) never shows it. Assigning in `init` doesn't fire the
    /// `didSet`, so restoring the flag doesn't re-write the same value.
    var showExtensionSetup: Bool = false {
        didSet {
            AppDefaults.store.set(showExtensionSetup, forKey: ExtensionSetupKey.pending)
        }
    }

    var readings: [ReadingRow] = []
    var boardSelection = BoardSelection<String>()

    /// The focused card remains the compatibility-facing selection for Gallery
    /// and the existing single-item reader actions.
    var selectedId: String? {
        get { boardSelection.focusedID }
        set {
            if let newValue {
                boardSelection.select(
                    newValue,
                    extending: false,
                    in: readings.map(\.id)
                )
            } else {
                boardSelection.clear()
            }
        }
    }

    var selectedIDs: Set<String> {
        boardSelection.selectedIDs
    }

    var selectedRows: [ReadingRow] {
        readings.filter { selectedIDs.contains($0.id) }
    }

    /// The reading-list search text, persisted across launches so a search the
    /// user left active is restored on reopen. `init` seeds it from the store.
    var searchQuery: String = "" {
        didSet {
            AppDefaults.store.set(searchQuery, forKey: FilterDefaultsKey.search)
        }
    }

    /// Pending debounced search reload. Each keystroke cancels the previous one
    /// so the core is queried once typing settles, not per character. Plumbing
    /// only — not part of the observable UI state.
    @ObservationIgnored var searchTask: Task<Void, Never>?
    @ObservationIgnored var saveNoticeTask: Task<Void, Never>?
    @ObservationIgnored var visualSearchTask: Task<Void, Never>?
    @ObservationIgnored var visualSearchRerunPending = false
    @ObservationIgnored var readingLoadGeneration: UInt64 = 0

    /// The active library scope. Always exactly one; `.all` is the unfiltered
    /// base. Persisted under a new key so legacy unread/read/archive selections
    /// cannot become invisible filters after those features disappear.
    var activeScope: LibraryScope = .all {
        didSet {
            AppDefaults.store.set(activeScope.rawValue, forKey: FilterDefaultsKey.scope)
        }
    }

    /// Readings awaiting delete confirmation, in their current board order.
    var pendingDelete: [ReadingRow]?

    /// Drives the tag-picker sheet for the open reading. Held here (rather than in
    /// the detail view) so both the toolbar button and the ⌘⇧T menu command can
    /// open it.
    var showTagSheet: Bool = false

    /// Drives the highlights inspector for the open reading. Opened from the
    /// Article menu and its ⌘⇧H shortcut.
    var showHighlights: Bool = false

    /// Drives the popover telling the user to select some text first, raised when
    /// the toolbar's Highlight button is pressed with nothing selected.
    var showHighlightHint: Bool = false

    /// Drives the keyboard-shortcuts cheat sheet (the ⌘/ command).
    var showShortcuts: Bool = false

    /// Highlights for the currently open reading. Drives both the reader's
    /// in-text tinting and the highlights inspector.
    var highlights: [HighlightRow] = []

    // ── Filter metadata ───────────────────────────────────────────────────

    /// Global tag names used by each reading's tag editor.
    var filters = LibraryFilters()

    // ── Status ────────────────────────────────────────────────────────────
    var isLoading: Bool = false
    /// File reconciliation can continue after a trusted cached board is visible.
    /// Kept separate from `isLoading` so it never hides usable cached readings.
    var isReconcilingLibrary: Bool = false
    var error: String?
    var isDeleting: Bool = false
    var activeLibraryWriteCount = 0
    /// Advances whenever the active core publishes newer file-backed content.
    /// Detail views include it in their load identity so an already-open cached
    /// reading revalidates after reconciliation or an incremental sync.
    var libraryContentGeneration: UInt64 = 0

    var canChangeLibrary: Bool {
        !isReconcilingLibrary && !isSaving && activeLibraryWriteCount == 0
    }

    func beginLibraryWrite() {
        activeLibraryWriteCount += 1
    }

    func endLibraryWrite() {
        activeLibraryWriteCount -= 1
    }

    /// Short, non-modal acknowledgement for paste/drop saves. Errors that stop
    /// the whole operation still use `error`; duplicates and partial results are
    /// routine status and stay out of an alert.
    var saveNotice: SaveNotice?
    var isSaving: Bool = false

    /// True while the user is editing a text field (the toolbar search field, the
    /// tag picker, …). macOS dispatches menu/context-menu key-equivalents *before*
    /// the focused field editor, so global shortcuts can fire mid-edit instead of
    /// editing the line. Commands whose shortcuts collide with the
    /// field editor's own keys disable themselves while this holds, letting the
    /// keystroke fall through to standard text editing. Kept in sync by
    /// `editingMonitor` (see `TextEditingMonitor`).
    var isEditingText: Bool = false
    var isFocusMode: Bool = false

    // Internal rather than private so the sibling extension files in this
    // folder can reach them — Swift's `private` is file-scoped.
    let semanticCandidateLimit = 2000
    var core: (any CoreBridging)?
    @ObservationIgnored var activeCoreID: ObjectIdentifier?
    @ObservationIgnored var hasUsableCachedLibrary = false
    @ObservationIgnored var librarySessionGeneration: UInt64 = 0
    @ObservationIgnored var libraryContentRefreshPending = false
    @ObservationIgnored var watcherSyncTask: Task<Void, Never>?
    @ObservationIgnored var watcherSyncPending = false
    var accessedURL: URL?
    var watcher: FolderWatcher?
    let visualSearchCoordinator: VisualSearchCoordinator?

    private var editingMonitor: TextEditingMonitor?

    init() {
        visualSearchCoordinator = Self.makeVisualSearchCoordinator()

        let defaults = AppDefaults.store

        // Removed sort controls must not leave an invisible preference behind.
        // The board now always uses its fixed newest-first / relevance ordering.
        defaults.removeObject(forKey: "sortField")
        defaults.removeObject(forKey: "sortAscending")
        defaults.removeObject(forKey: FilterDefaultsKey.kind)
        defaults.removeObject(forKey: FilterDefaultsKey.tag)

        // Restore a current scope. Retired read/archive/favorite/note values become
        // All so a removed control can never leave an invisible filter active.
        // The old rating filter is discarded.
        let persistedScope = defaults.string(forKey: FilterDefaultsKey.scope)
            .flatMap(LibraryScope.init(rawValue:))
        activeScope = persistedScope ?? .all
        defaults.set(activeScope.rawValue, forKey: FilterDefaultsKey.scope)
        defaults.removeObject(forKey: FilterDefaultsKey.legacyView)
        defaults.removeObject(forKey: FilterDefaultsKey.legacyRating)
        searchQuery = defaults.string(forKey: FilterDefaultsKey.search) ?? ""

        // Resume the extension-install step if the user quit before dismissing it.
        // Set before the restore boot below so, once boot flips `libraryURL`, the
        // step shows immediately with no reading-list flash.
        showExtensionSetup = defaults.bool(forKey: ExtensionSetupKey.pending)

        if TestHooks.isUITesting {
            // UI-testing: never resolve the persisted bookmark (leave the dev's
            // real library untouched). Boot the pinned temp library if one was
            // given; otherwise fall through to the onboarding screen.
            if let path = TestHooks.libraryPath {
                let url = URL(fileURLWithPath: path)
                libraryURL = url
                isRestoringLibrary = true
                Task { await boot(url: url) }
            }
        } else if let url = LibraryBookmark.resolve() {
            accessedURL = url
            libraryURL = url
            isRestoringLibrary = true
            Task { await boot(url: url) }
        }

        editingMonitor = TextEditingMonitor { [weak self] editing in
            self?.isEditingText = editing
        }
    }

    private static func makeVisualSearchCoordinator() -> VisualSearchCoordinator? {
        // Never donate throwaway fixture IDs to the user's real Spotlight index
        // or introduce system-model timing into UI tests.
        guard !TestHooks.isUITesting else { return nil }
        return VisualSearchCoordinator(
            analyzer: AppleVisualAnalyzer(),
            analyzerVersion: AppleVisualAnalyzer.analyzerVersion,
            spotlight: SpotlightVisualIndex()
        )
    }

    // ── Extension setup ─────────────────────────────────────────────────────────

    /// Whether the user has finished the extension-install step. Once set it stays
    /// set, so a later re-pick of the library (Settings › Change Library…) doesn't
    /// resurface the step — it's a first-run-only prompt.
    var hasCompletedExtensionSetup: Bool {
        AppDefaults.store.bool(forKey: ExtensionSetupKey.completed)
    }

    /// Dismiss the extension-install step and remember it's done for good. Backs
    /// the step's "Continue" button.
    func completeExtensionSetup() {
        AppDefaults.store.set(true, forKey: ExtensionSetupKey.completed)
        showExtensionSetup = false
    }

    // ── Search focus ──────────────────────────────────────────────────────────

    /// Focus the native searchable field (⌘K). SwiftUI exposes no focus binding
    /// for toolbar search on macOS, so reach its `NSSearchField` through AppKit.
    func focusSearchField() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        // The toolbar is hosted alongside `contentView`, not within it, so search
        // from the frame view (their shared ancestor) to reach the field.
        let root = window.contentView?.superview ?? window.contentView
        guard let root, let field = Self.firstSearchField(in: root) else { return }
        window.makeFirstResponder(field)
    }

    private static func firstSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField {
            return field
        }
        for subview in view.subviews {
            if let field = firstSearchField(in: subview) {
                return field
            }
        }
        return nil
    }
}
