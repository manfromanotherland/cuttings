// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // ── Navigation state ──────────────────────────────────────────────────
    @Published var libraryURL: URL?
    @Published var readings: [FfiReadingRow] = []
    @Published var searchResults: [FfiSearchResult] = []
    @Published var selectedId: String?
    @Published var searchQuery: String = ""
    @Published var activeView: SidebarItem = .all
    @Published var selectedTag: String?
    @Published var sortNewestFirst: Bool = true

    // ── Sidebar metadata ──────────────────────────────────────────────────
    @Published var viewCounts: [SidebarItem: Int] = [:]
    @Published var allTags: [FfiTagCount] = []

    // ── Status ────────────────────────────────────────────────────────────
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var core: CoreBridge?
    private var accessedURL: URL?
    private var watcher: LibraryWatcher?

    init() {
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
                    sortNewestFirst: sortNewestFirst,
                    tag: selectedTag,
                    since: nil, until: nil,
                    limit: 200, offset: 0
                )
                readings = try await core.listReadings(opts: opts)
            } else {
                let results = try await core.search(query: searchQuery, limit: 50)
                searchResults = results
                let ids = Set(results.map(\.id))
                let opts = FfiListOptions(
                    view: .all, sortNewestFirst: true,
                    tag: nil, since: nil, until: nil,
                    limit: 1000, offset: 0
                )
                let all = try await core.listReadings(opts: opts)
                readings = all.filter { ids.contains($0.id) }
                    .sorted { a, b in
                        // Preserve search rank order.
                        let ai = results.firstIndex(where: { $0.id == a.id }) ?? Int.max
                        let bi = results.firstIndex(where: { $0.id == b.id }) ?? Int.max
                        return ai < bi
                    }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // ── Sidebar counts & tags ─────────────────────────────────────────────

    func loadSidebar() async {
        guard let core else { return }
        do {
            var counts: [SidebarItem: Int] = [:]
            for item in SidebarItem.allCases {
                let opts = FfiListOptions(
                    view: item.ffiView, sortNewestFirst: true,
                    tag: nil, since: nil, until: nil,
                    limit: 9999, offset: 0
                )
                counts[item] = try await core.listReadings(opts: opts).count
            }
            viewCounts = counts
            allTags = try await core.listTags()
        } catch {
            // Sidebar counts are non-critical; don't surface as an error.
        }
    }

    // ── Tag navigation ────────────────────────────────────────────────────

    func selectTag(_ tag: String) async {
        selectedTag = tag
        activeView = .all
        await loadReadings()
    }

    func clearTag() async {
        selectedTag = nil
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

// ── Sidebar items ──────────────────────────────────────────────────────────────

enum SidebarItem: String, CaseIterable, Identifiable {
    case all, unread, archive, favorites
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .archive: "Archive"
        case .favorites: "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .unread: "circle"
        case .archive: "archivebox"
        case .favorites: "star"
        }
    }

    var ffiView: FfiView {
        switch self {
        case .all: .all
        case .unread: .unread
        case .archive: .archive
        case .favorites: .favorites
        }
    }
}
