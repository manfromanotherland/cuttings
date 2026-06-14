// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

/// Central observable state shared across the app via `@EnvironmentObject`.
///
/// On first launch `libraryURL` is nil; the UI shows the onboarding sheet.
/// Once the user picks a folder, `chooseLibrary()` saves a security-scoped
/// bookmark so the app re-opens it on every subsequent launch without prompting.
@MainActor
final class AppState: ObservableObject {
    @Published var libraryURL: URL?
    @Published var readings: [FfiReadingRow] = []
    @Published var selectedId: String?
    @Published var searchQuery: String = ""
    @Published var activeView: SidebarItem = .all
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var core: CoreBridge?
    private var accessedURL: URL?

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
            await loadReadings()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // ── List / search ─────────────────────────────────────────────────────

    func loadReadings() async {
        guard let core else { return }
        do {
            if searchQuery.isEmpty {
                let opts = FfiListOptions(
                    view: activeView.ffiView,
                    sortNewestFirst: true,
                    tag: nil, since: nil, until: nil,
                    limit: 100, offset: 0
                )
                readings = try await core.listReadings(opts: opts)
            } else {
                let results = try await core.search(query: searchQuery, limit: 50)
                let opts = FfiListOptions(
                    view: .all,
                    sortNewestFirst: true,
                    tag: nil, since: nil, until: nil,
                    limit: 200, offset: 0
                )
                let all = try await core.listReadings(opts: opts)
                let ids = Set(results.map(\.id))
                readings = all.filter { ids.contains($0.id) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // ── Mutations ─────────────────────────────────────────────────────────

    func toggleRead(_ row: FfiReadingRow) async {
        guard let core else { return }
        try? await core.setRead(id: row.id, read: !row.read)
        await loadReadings()
    }

    func toggleFavorite(_ row: FfiReadingRow) async {
        guard let core else { return }
        try? await core.setFavorite(id: row.id, favorite: !row.favorite)
        await loadReadings()
    }

    func archive(_ row: FfiReadingRow) async {
        guard let core else { return }
        try? await core.setArchived(id: row.id, archived: true)
        await loadReadings()
    }

    func addTag(id: String, tag: String) async {
        guard let core else { return }
        try? await core.addTag(id: id, tag: tag)
        await loadReadings()
    }

    func removeTag(id: String, tag: String) async {
        guard let core else { return }
        try? await core.removeTag(id: id, tag: tag)
        await loadReadings()
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
