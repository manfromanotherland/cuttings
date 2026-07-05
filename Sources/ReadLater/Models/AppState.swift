// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import AppKit
import Observation

/// User-selectable sort field for the reading list. Mirrors the core's
/// `FfiSortField`; persisted as its `rawValue` in `UserDefaults`.
enum ReadingSort: String, CaseIterable, Identifiable {
    case savedAt
    case readAt
    case rating
    case timeToRead

    var id: String { rawValue }

    /// Label shown in the sort-field picker.
    var label: String {
        switch self {
        case .savedAt: "Date saved"
        case .readAt: "Date read"
        case .rating: "Rating"
        case .timeToRead: "Time to read"
        }
    }

    var ffi: FfiSortField {
        switch self {
        case .savedAt: .savedAt
        case .readAt: .readAt
        case .rating: .rating
        case .timeToRead: .wordCount
        }
    }

    /// Direction label tailored to the field (e.g. "Newest first" vs
    /// "Highest rated"), for the ascending/descending picker.
    func directionLabel(ascending: Bool) -> String {
        switch self {
        case .savedAt: ascending ? "Oldest first" : "Newest first"
        case .readAt: ascending ? "Read least recently" : "Read most recently"
        case .rating: ascending ? "Lowest rated" : "Highest rated"
        case .timeToRead: ascending ? "Shortest first" : "Longest first"
        }
    }
}

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
    var searchResults: [FfiSearchResult] = []
    var selectedId: String?
    var searchQuery: String = ""

    /// Pending debounced search reload. Each keystroke cancels the previous one
    /// so the core is queried once typing settles, not per character. Plumbing
    /// only — not part of the observable UI state.
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    var sidebarSelection: SidebarSelection? = .view(.all)

    /// Sort field for the reading list, persisted across launches. The default
    /// here only initializes the backing store; `init` immediately overwrites it
    /// with the persisted preference (re-persisting the same value harmlessly).
    var sortField: ReadingSort = .savedAt {
        didSet {
            UserDefaults.standard.set(sortField.rawValue, forKey: SortDefaultsKey.field)
        }
    }

    /// Sort direction (ascending when `true`), persisted across launches.
    /// Descending is the default for every field.
    var sortAscending: Bool = false {
        didSet {
            UserDefaults.standard.set(sortAscending, forKey: SortDefaultsKey.ascending)
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
        if case .rating(let r) = sidebarSelection { return r }
        return nil
    }

    // ── Sidebar metadata ──────────────────────────────────────────────────
    var viewCounts: [SidebarItem: Int] = [:]
    var allTags: [FfiTagCount] = []
    var allRatings: [FfiRatingCount] = []

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
    /// `startTextEditingMonitor`.
    var isEditingText: Bool = false

    private let pageSize: UInt32 = 100

    private var core: CoreBridge?
    private var accessedURL: URL?
    private var watcher: LibraryWatcher?

    /// Tokens for the text-editing focus observers; removed in `deinit`.
    /// `nonisolated(unsafe)` so the `nonisolated deinit` can read them to tear
    /// down: they're only written on the main actor (in `init`) and read once at
    /// deinit, which has exclusive access — so there's no actual race to guard.
    nonisolated(unsafe) private var editingObservers: [NSObjectProtocol] = []

    init() {
        // Restore the persisted sort preference (defaults: saved-at, descending).
        let defaults = UserDefaults.standard
        sortField = defaults.string(forKey: SortDefaultsKey.field)
            .flatMap(ReadingSort.init(rawValue:)) ?? .savedAt
        sortAscending = defaults.bool(forKey: SortDefaultsKey.ascending)

        if let url = LibraryBookmark.resolve() {
            accessedURL = url
            isRestoringLibrary = true
            Task { await boot(url: url) }
        }

        startTextEditingMonitor()
    }

    deinit {
        let center = NotificationCenter.default
        editingObservers.forEach { center.removeObserver($0) }
    }

    // ── Text-editing focus ──────────────────────────────────────────────────
    // macOS routes menu key-equivalents ahead of the focused field editor, so a
    // global ⌘⌫ ("Archive") fires even while the user is deleting a line in a
    // text field. We publish `isEditingText` so colliding commands can disable
    // themselves while a field is focused. Rather than wire focus into every
    // field, we watch the field editor's begin/end-editing notifications (and key
    // window changes) and re-read the key window's first responder — one place,
    // covering the search field, the tag picker, and any field added later.

    private func startTextEditingMonitor() {
        let names: [Notification.Name] = [
            NSText.didBeginEditingNotification,
            NSText.didEndEditingNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
        ]
        let center = NotificationCenter.default
        editingObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Delivery on `.main` runs on the main thread, so it's safe to
                // assume MainActor isolation and read AppKit/UI state directly.
                MainActor.assumeIsolated { self?.refreshEditingState() }
            }
        }
    }

    private func refreshEditingState() {
        let editing = Self.firstResponderIsTextInput()
        if editing != isEditingText { isEditingText = editing }
    }

    /// Whether the key window's first responder is an editable text input — the
    /// field editor behind a `TextField`/search field, or an editable `NSTextView`.
    /// The reader's selectable-but-read-only text view is intentionally excluded:
    /// there's no line to delete there, so its shortcuts should keep working.
    private static func firstResponderIsTextInput() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isFieldEditor || textView.isEditable
        }
        return responder is NSText
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

    // ── Onboarding ────────────────────────────────────────────────────────

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Library Folder"
        panel.message = "Select or create a folder to store your articles."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await pickLibrary(url: url) }
    }

    private func pickLibrary(url: URL) async {
        do {
            try LibrarySetup.scaffold(at: url)
            try LibraryBookmark.save(url: url)
            stopAccessing()
            accessedURL = LibraryBookmark.resolve()
            await boot(url: url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // ── Boot ──────────────────────────────────────────────────────────────

    func boot(url: URL) async {
        isLoading = true
        error = nil
        do {
            let bridge = try CoreBridge(libraryPath: url.path, dbPath: Self.dbPath())
            try await bridge.rebuild()
            core = bridge
            libraryURL = url
            writeLibraryPathConfig(url.path)
            HostInstaller.installIfNeeded()
            startWatcher(libraryPath: url.path)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        isRestoringLibrary = false
    }

    /// Write the library path to ~/.config/read-later/library so the native
    /// messaging host can find it without needing a security-scoped bookmark.
    private func writeLibraryPathConfig(_ path: String) {
        let configDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/read-later", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: configDir, withIntermediateDirectories: true)
        try? (path + "\n").write(
            to: configDir.appendingPathComponent("library"),
            atomically: true, encoding: .utf8)
    }

    // ── Refresh (list + sidebar) ──────────────────────────────────────────

    func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            // A refresh follows a local mutation (or a watcher sync): never
            // re-home the selection here. The mutation already set the selection
            // it wants — advancing to a neighbour, or deliberately staying on a
            // row it just filtered out (e.g. re-rating the open article while in
            // a rating filter). Stealing it would desync the list highlight from
            // the open reading and strand the phantom-selected next row.
            group.addTask { await self.loadReadings(resetSelectionIfMissing: false) }
            group.addTask { await self.loadSidebar() }
        }
    }

    // ── List / search ─────────────────────────────────────────────────────

    /// Entry point for search-field edits. Debounces rapid typing so the core
    /// runs a single search once input settles (~150ms) instead of one pass per
    /// keystroke; each edit cancels the previous pending reload. Non-search
    /// reloads (filter, sort, refresh) call `loadReadings` directly and stay
    /// immediate.
    func searchDidChange() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            // This reload fires ~150ms after the last keystroke, while the search
            // field is still focused. Re-homing the list selection here moves
            // first responder to the list, flips `isEditingText` false, and lets
            // ⌘⌫ (Archive) fire instead of deleting to the start of the search
            // term. So while a text field is being edited, leave the selection
            // put to keep focus in the field; re-home only when not editing.
            await self.loadReadings(resetSelectionIfMissing: !self.isEditingText)
        }
    }

    /// `resetSelectionIfMissing` controls what happens when the current
    /// selection isn't in the freshly loaded list. Direct (re)loads — filter
    /// switch, sort, search, first load — pass `true` to re-home onto the first
    /// row. A `refresh()` after a local mutation passes `false` to leave the
    /// selection alone (see `refresh()`). An empty selection always defaults to
    /// the first row either way.
    func loadReadings(resetSelectionIfMissing: Bool = true) async {
        guard let core else { return }
        do {
            if searchQuery.isEmpty {
                searchResults = []
                let opts = FfiListOptions(
                    view: activeView.ffiView,
                    sort: sortField.ffi,
                    ascending: sortAscending,
                    tag: selectedTag,
                    rating: selectedRating,
                    since: nil, until: nil,
                    limit: pageSize, offset: 0
                )
                let result = try await core.listReadings(opts: opts)
                readings = result
                hasMoreReadings = result.count == Int(pageSize)
            } else {
                hasMoreReadings = false
                let results = try await core.search(query: searchQuery, limit: 50)
                searchResults = results
                // Hydrate full rows straight from the ranked hit ids. Search
                // spans both active and archived readings, so we must not route
                // through a `.all` listing (archived = 0) — that would silently
                // drop archived matches. Fetching by id also preserves BM25 rank
                // order for free and avoids any list-size cap.
                readings = try await core.getReadingRows(ids: results.map(\.id))
            }

            // Open the first reading by default so selection-dependent UI (the
            // reader and its toolbar, including Sort) is visible without an extra
            // click. A missing selection is re-homed to the first item only when
            // the caller asked (direct reloads); a post-mutation refresh leaves a
            // deliberately off-list selection — the open reading — in place.
            if selectedId == nil
                || (resetSelectionIfMissing && !readings.contains(where: { $0.id == selectedId })) {
                selectedId = readings.first?.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMoreReadings() async {
        guard hasMoreReadings, !isLoadingMore, searchQuery.isEmpty, let core else { return }
        isLoadingMore = true
        do {
            let opts = FfiListOptions(
                view: activeView.ffiView,
                sort: sortField.ffi,
                ascending: sortAscending,
                tag: selectedTag,
                rating: selectedRating,
                since: nil, until: nil,
                limit: pageSize, offset: UInt32(readings.count)
            )
            let result = try await core.listReadings(opts: opts)
            readings.append(contentsOf: result)
            hasMoreReadings = result.count == Int(pageSize)
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingMore = false
    }

    // ── Sidebar counts & tags ─────────────────────────────────────────────

    func loadSidebar() async {
        guard let core else { return }
        do {
            // One grouped COUNT query for all five badges, instead of
            // materializing up to 9,999 full rows per view. This is only the
            // authoritative recount — the optimistic `applySidebarDelta` path
            // still updates the badges within a frame and reconciles here.
            let c = try await core.viewCounts()
            viewCounts = [
                .all: Int(c.all),
                .unread: Int(c.unread),
                .read: Int(c.read),
                .archive: Int(c.archive),
                .favorites: Int(c.favorites),
            ]
            allTags = try await core.listTags()
            allRatings = try await core.listRatings()
        } catch {
            // Sidebar counts are non-critical; don't surface as an error.
        }
    }

    // ── Tag navigation ────────────────────────────────────────────────────

    func selectTag(_ tag: String) async {
        sidebarSelection = .tag(tag)
        await loadReadings()
    }

    func clearTag() async {
        sidebarSelection = .view(.all)
        await loadReadings()
    }

    // ── Incremental sync (FSEvents) ───────────────────────────────────────

    func sync() async {
        guard let core else { return }
        do {
            let changed = try await core.sync()
            if changed > 0 { await refresh() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startWatcher(libraryPath: String) {
        // Tear down the previous watcher before replacing it. Reassigning alone
        // would leak it — the FSEvents stream keeps it alive, still watching the
        // old folder and firing sync() against the new library. invalidate()
        // runs while we still hold the strong reference, so the release it
        // triggers can't deallocate the watcher mid-teardown.
        watcher?.invalidate()
        watcher = LibraryWatcher(libraryPath: libraryPath) { [weak self] in
            Task { @MainActor [weak self] in await self?.sync() }
        }
    }

    // ── Mutations ─────────────────────────────────────────────────────────

    /// Optimistically apply an edit so it shows on the next frame, before the
    /// core write + `refresh()` land: swap the row in the visible list (if
    /// present) and fold the before/after into the sidebar aggregates. Removing a
    /// row that no longer matches the filter is the separate, explicit job of
    /// `advancePastFilteredRow`; re-ordering is left to the follow-up `refresh()`.
    /// A failed write self-heals: the refresh re-reads the index and overwrites
    /// both the row and the counts.
    private func applyOptimistic(_ old: FfiReadingRow, _ new: FfiReadingRow) {
        if let i = readings.firstIndex(where: { $0.id == old.id }) {
            readings[i] = new
        }
        applySidebarDelta(from: old, to: new)
    }

    /// Fold a row's before/after state into the sidebar counts (view counts, tag
    /// counts, rating counts), mirroring the core's count rules so the optimistic
    /// numbers match what `loadSidebar()` reconciles to: view counts follow the
    /// `list.rs` clauses (Favorites counts regardless of archived); tag and rating
    /// counts include only non-archived readings (`tags.rs` / `rating.rs`).
    private func applySidebarDelta(from old: FfiReadingRow, to new: FfiReadingRow) {
        func inView(_ item: SidebarItem, _ r: FfiReadingRow) -> Bool {
            switch item {
            case .all:       !r.archived
            case .unread:    !r.archived && !r.read
            case .read:      !r.archived && r.read
            case .archive:   r.archived
            case .favorites: r.favorite
            }
        }
        for item in SidebarItem.allCases {
            let delta = (inView(item, new) ? 1 : 0) - (inView(item, old) ? 1 : 0)
            if delta != 0 { viewCounts[item] = max(0, (viewCounts[item] ?? 0) + delta) }
        }

        func tagContributes(_ r: FfiReadingRow, _ tag: String) -> Bool {
            !r.archived && r.tags.contains(tag)
        }
        for tag in Set(old.tags).union(new.tags) {
            let delta = (tagContributes(new, tag) ? 1 : 0) - (tagContributes(old, tag) ? 1 : 0)
            if delta != 0 { bumpTag(tag, by: delta) }
        }

        func ratingBucket(_ r: FfiReadingRow) -> UInt8? {
            (!r.archived && (1...5).contains(r.rating)) ? r.rating : nil
        }
        let oldBucket = ratingBucket(old), newBucket = ratingBucket(new)
        if oldBucket != newBucket {
            if let oldBucket { bumpRating(oldBucket, by: -1) }
            if let newBucket { bumpRating(newBucket, by: 1) }
        }
    }

    /// Adjust a tag's count, dropping it at zero and inserting it when it first
    /// appears, then re-sort to match `list_tags` (count desc, then name asc).
    private func bumpTag(_ tag: String, by delta: Int) {
        if let i = allTags.firstIndex(where: { $0.tag == tag }) {
            let n = Int(allTags[i].count) + delta
            if n <= 0 { allTags.remove(at: i) } else { allTags[i].count = UInt64(n) }
        } else if delta > 0 {
            allTags.append(FfiTagCount(tag: tag, count: UInt64(delta)))
        }
        allTags.sort { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// Adjust a star bucket's count, dropping it at zero and inserting it when it
    /// first appears, keeping `list_ratings`' highest-first order.
    private func bumpRating(_ rating: UInt8, by delta: Int) {
        if let i = allRatings.firstIndex(where: { $0.rating == rating }) {
            let n = Int(allRatings[i].count) + delta
            if n <= 0 { allRatings.remove(at: i) } else { allRatings[i].count = UInt64(n) }
        } else if delta > 0 {
            allRatings.append(FfiRatingCount(rating: rating, count: UInt64(delta)))
        }
        allRatings.sort { $0.rating > $1.rating }
    }

    /// Mirror of the core's view/tag/rating filter (see `list.rs`): does `row`
    /// still belong in the list the user is currently looking at?
    private func rowMatchesCurrentFilter(_ row: FfiReadingRow) -> Bool {
        switch activeView {
        case .all:       if row.archived { return false }
        case .unread:    if row.archived || row.read { return false }
        case .read:      if row.archived || !row.read { return false }
        case .archive:   if !row.archived { return false }
        case .favorites: if !row.favorite { return false }
        }
        if let tag = selectedTag, !row.tags.contains(tag) { return false }
        if let rating = selectedRating, row.rating != rating { return false }
        return true
    }

    /// Pair with `applyOptimistic` for status changes: if the optimistic edit
    /// pushed the row out of the current filter, slide it out and advance the
    /// selection to an adjacent row in the *same* render tick — one motion, not
    /// an in-place icon flip followed a beat later by the row jumping away. A
    /// no-op when the row still matches (e.g. marking read in the All view).
    /// Skipped during search, whose results span every view.
    private func advancePastFilteredRow(id: String) {
        guard searchQuery.isEmpty,
              let i = readings.firstIndex(where: { $0.id == id }),
              !rowMatchesCurrentFilter(readings[i]) else { return }
        withAnimation {
            if selectedId == id {
                selectedId = i + 1 < readings.count ? readings[i + 1].id
                    : (i > 0 ? readings[i - 1].id : nil)
            }
            readings.remove(at: i)
        }
    }

    func toggleRead(_ row: FfiReadingRow) async {
        guard let core else { return }
        var updated = row
        updated.read = !row.read
        applyOptimistic(row, updated)
        advancePastFilteredRow(id: row.id)
        try? await core.setRead(id: row.id, read: updated.read)
        await refresh()
    }

    func toggleFavorite(_ row: FfiReadingRow) async {
        guard let core else { return }
        var updated = row
        updated.favorite = !row.favorite
        applyOptimistic(row, updated)
        advancePastFilteredRow(id: row.id)
        try? await core.setFavorite(id: row.id, favorite: updated.favorite)
        await refresh()
    }

    /// Set a reading's star rating (0–5, 0 clears it). Returns the refreshed
    /// row so detail views can update their local copy.
    @discardableResult
    func setRating(id: String, rating: UInt8) async -> FfiReadingRow? {
        guard let core else { return nil }
        if let old = readings.first(where: { $0.id == id }) {
            var updated = old
            updated.rating = rating
            applyOptimistic(old, updated)
        }
        try? await core.setRating(id: id, rating: rating)
        await refresh()
        // The row may have left the current filtered list (e.g. its rating no
        // longer matches), so fall back to fetching it straight from the index.
        if let row = readings.first(where: { $0.id == id }) { return row }
        return try? await core.getReadingRow(id: id)
    }

    func archive(_ row: FfiReadingRow) async {
        guard let core else { return }
        var updated = row
        updated.archived = true
        applyOptimistic(row, updated)
        advancePastFilteredRow(id: row.id)
        try? await core.setArchived(id: row.id, archived: true)
        await refresh()
    }

    func unarchive(_ row: FfiReadingRow) async {
        guard let core else { return }
        var updated = row
        updated.archived = false
        applyOptimistic(row, updated)
        advancePastFilteredRow(id: row.id)
        try? await core.setArchived(id: row.id, archived: false)
        await refresh()
    }

    /// Permanently delete a reading: removes its file and assets from disk and
    /// its row from the index. Irreversible — callers should confirm first.
    func delete(_ row: FfiReadingRow) async {
        guard let core else { return }
        do {
            try await core.deleteReading(id: row.id)
            if selectedId == row.id { selectedId = nil }
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addTag(id: String, tag: String) async {
        guard let core else { return }
        // Mirror the core: trim, dedup on exact match, append (no sort/lowercase),
        // so the optimistic chip lands in the same place the reload confirms.
        let tag = tag.trimmingCharacters(in: .whitespaces)
        if let old = readings.first(where: { $0.id == id }), !old.tags.contains(tag) {
            var updated = old
            updated.tags.append(tag)
            applyOptimistic(old, updated)
        }
        try? await core.addTag(id: id, tag: tag)
        await refresh()
    }

    func removeTag(id: String, tag: String) async {
        guard let core else { return }
        if let old = readings.first(where: { $0.id == id }), old.tags.contains(tag) {
            var updated = old
            updated.tags.removeAll { $0 == tag }
            applyOptimistic(old, updated)
        }
        try? await core.removeTag(id: id, tag: tag)
        await refresh()
    }

    func getBody(id: String) async -> String? {
        guard let core else { return nil }
        return try? await core.getBody(id: id)
    }

    // ── Highlights ────────────────────────────────────────────────────────

    /// Load the highlights for `id` into `highlights`. Pass `nil` to clear
    /// (e.g. when no reading is selected).
    func loadHighlights(id: String?) async {
        guard let core, let id else { highlights = []; return }
        highlights = (try? await core.listHighlights(readingId: id)) ?? []
    }

    /// Save a new highlight for `id` from the user's selected text, then reload.
    func addHighlight(id: String, text: String) async {
        guard let core else { return }
        do {
            try await core.addHighlight(readingId: id, text: text)
            await loadHighlights(id: id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Toggle a highlight for `id`: clears it if the exact passage is already
    /// highlighted, otherwise adds it. Reloads either way.
    func toggleHighlight(id: String, text: String) async {
        guard let core else { return }
        do {
            try await core.toggleHighlight(readingId: id, text: text)
            await loadHighlights(id: id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Remove a single highlight from `id`, then reload.
    func deleteHighlight(id: String, highlightId: String) async {
        guard let core else { return }
        try? await core.deleteHighlight(readingId: id, highlightId: highlightId)
        await loadHighlights(id: id)
    }

    /// Re-fetch a single reading row from the index (e.g. after a tag edit) so
    /// detail views can refresh their local copy without a full list reload.
    func reloadRow(id: String) async -> FfiReadingRow? {
        guard let core else { return nil }
        return try? await core.getReadingRow(id: id)
    }

    // ── Security-scoped resource ──────────────────────────────────────────

    private func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    static func dbPath() -> String {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReadLater", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("index.db").path
    }
}

// ── Sidebar selection ────────────────────────────────────────────────────────
// A single selectable identity for the sidebar `List`, covering both the smart
// views and tag filters so SwiftUI can drive native row highlighting for both.

enum SidebarSelection: Hashable {
    case view(SidebarItem)
    case tag(String)
    case rating(UInt8)
}

// ── Sidebar items ──────────────────────────────────────────────────────────────

enum SidebarItem: String, CaseIterable, Identifiable {
    case all, unread, read, archive, favorites
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .read: "Read"
        case .archive: "Archive"
        case .favorites: "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .unread: "circle"
        case .read: "checkmark.circle"
        case .archive: "archivebox"
        case .favorites: "heart"
        }
    }

    var ffiView: FfiView {
        switch self {
        case .all: .all
        case .unread: .unread
        case .read: .read
        case .archive: .archive
        case .favorites: .favorites
        }
    }
}
