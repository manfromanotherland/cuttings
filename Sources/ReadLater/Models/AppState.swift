// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

/// User-selectable sort field for the reading list. Mirrors the core's
/// `FfiSortField`; persisted as its `rawValue` in `UserDefaults`.
enum ReadingSort: String, CaseIterable, Identifiable {
    case savedAt
    case readAt
    case rating

    var id: String { rawValue }

    /// Label shown in the sort-field picker.
    var label: String {
        switch self {
        case .savedAt: "Date saved"
        case .readAt: "Date read"
        case .rating: "Rating"
        }
    }

    var ffi: FfiSortField {
        switch self {
        case .savedAt: .savedAt
        case .readAt: .readAt
        case .rating: .rating
        }
    }

    /// Direction label tailored to the field (e.g. "Newest first" vs
    /// "Highest rated"), for the ascending/descending picker.
    func directionLabel(ascending: Bool) -> String {
        switch self {
        case .savedAt: ascending ? "Oldest first" : "Newest first"
        case .readAt: ascending ? "Read least recently" : "Read most recently"
        case .rating: ascending ? "Lowest rated" : "Highest rated"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    private enum SortDefaultsKey {
        static let field = "sortField"
        static let ascending = "sortAscending"
    }
    // ── Navigation state ──────────────────────────────────────────────────
    @Published var libraryURL: URL?
    @Published var readings: [FfiReadingRow] = []
    @Published var searchResults: [FfiSearchResult] = []
    @Published var selectedId: String?
    @Published var searchQuery: String = ""
    @Published var sidebarSelection: SidebarSelection? = .view(.all)

    /// Sort field for the reading list, persisted across launches.
    @Published var sortField: ReadingSort {
        didSet {
            UserDefaults.standard.set(sortField.rawValue, forKey: SortDefaultsKey.field)
        }
    }

    /// Sort direction (ascending when `true`), persisted across launches.
    /// Descending is the default for every field.
    @Published var sortAscending: Bool {
        didSet {
            UserDefaults.standard.set(sortAscending, forKey: SortDefaultsKey.ascending)
        }
    }

    /// Reading awaiting delete confirmation, if any. Drives the confirm dialog.
    @Published var pendingDelete: FfiReadingRow?

    /// Highlights for the currently open reading. Drives both the reader's
    /// in-text tinting and the highlights inspector.
    @Published var highlights: [FfiHighlight] = []

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
    @Published var viewCounts: [SidebarItem: Int] = [:]
    @Published var allTags: [FfiTagCount] = []
    @Published var allRatings: [FfiRatingCount] = []

    // ── Status ────────────────────────────────────────────────────────────
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreReadings: Bool = false
    @Published var error: String?

    private let pageSize: UInt32 = 100

    private var core: CoreBridge?
    private var accessedURL: URL?
    private var watcher: LibraryWatcher?

    init() {
        // Restore the persisted sort preference (defaults: saved-at, descending).
        let defaults = UserDefaults.standard
        sortField = defaults.string(forKey: SortDefaultsKey.field)
            .flatMap(ReadingSort.init(rawValue:)) ?? .savedAt
        sortAscending = defaults.bool(forKey: SortDefaultsKey.ascending)

        if let url = LibraryBookmark.resolve() {
            accessedURL = url
            Task { await boot(url: url) }
        }
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
            group.addTask { await self.loadReadings() }
            group.addTask { await self.loadSidebar() }
        }
    }

    // ── List / search ─────────────────────────────────────────────────────

    func loadReadings() async {
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
            // reader and its toolbar, including Sort) is visible without an
            // extra click. If the previous selection is gone after a reload,
            // fall back to the first item; clear it only when the list is empty.
            if selectedId == nil || !readings.contains(where: { $0.id == selectedId }) {
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
            var counts: [SidebarItem: Int] = [:]
            for item in SidebarItem.allCases {
                let opts = FfiListOptions(
                    view: item.ffiView, sort: .savedAt, ascending: false,
                    tag: nil, rating: nil, since: nil, until: nil,
                    limit: 9999, offset: 0
                )
                counts[item] = try await core.listReadings(opts: opts).count
            }
            viewCounts = counts
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
        watcher = LibraryWatcher(libraryPath: libraryPath) { [weak self] in
            Task { @MainActor [weak self] in await self?.sync() }
        }
    }

    // ── Mutations ─────────────────────────────────────────────────────────

    func toggleRead(_ row: FfiReadingRow) async {
        guard let core else { return }
        try? await core.setRead(id: row.id, read: !row.read)
        await refresh()
    }

    func toggleFavorite(_ row: FfiReadingRow) async {
        guard let core else { return }
        try? await core.setFavorite(id: row.id, favorite: !row.favorite)
        await refresh()
    }

    /// Set a reading's star rating (0–5, 0 clears it). Returns the refreshed
    /// row so detail views can update their local copy.
    @discardableResult
    func setRating(id: String, rating: UInt8) async -> FfiReadingRow? {
        guard let core else { return nil }
        try? await core.setRating(id: id, rating: rating)
        await refresh()
        // The row may have left the current filtered list (e.g. its rating no
        // longer matches), so fall back to fetching it straight from the index.
        if let row = readings.first(where: { $0.id == id }) { return row }
        return try? await core.getReadingRow(id: id)
    }

    func archive(_ row: FfiReadingRow) async {
        guard let core else { return }
        try? await core.setArchived(id: row.id, archived: true)
        await refresh()
    }

    func unarchive(_ row: FfiReadingRow) async {
        guard let core else { return }
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
        try? await core.addTag(id: id, tag: tag)
        await refresh()
    }

    func removeTag(id: String, tag: String) async {
        guard let core else { return }
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
