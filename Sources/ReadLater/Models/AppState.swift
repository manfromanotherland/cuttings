// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

/// Central observable state shared across the app via `@EnvironmentObject`.
///
/// On first launch the library folder hasn't been chosen yet; `libraryPath`
/// will be nil and the UI shows the onboarding sheet (MAC-2).
@MainActor
final class AppState: ObservableObject {
    @Published var libraryPath: String? = Self.storedLibraryPath()
    @Published var readings: [FfiReadingRow] = []
    @Published var selectedId: String?
    @Published var searchQuery: String = ""
    @Published var activeView: SidebarItem = .all
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var core: CoreBridge?

    init() {
        if let path = libraryPath {
            Task { await boot(libraryPath: path) }
        }
    }

    // ── Boot ──────────────────────────────────────────────────────────────

    func boot(libraryPath path: String) async {
        isLoading = true
        error = nil
        do {
            let dbPath = Self.dbPath()
            let bridge = try CoreBridge(libraryPath: path, dbPath: dbPath)
            try await bridge.rebuild()
            core = bridge
            libraryPath = path
            Self.storeLibraryPath(path)
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
                    tag: nil,
                    since: nil,
                    until: nil,
                    limit: 100,
                    offset: 0
                )
                readings = try await core.listReadings(opts: opts)
            } else {
                let results = try await core.search(query: searchQuery, limit: 50)
                // Convert search results to display rows via a light list fetch.
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

    // ── Persistence helpers ────────────────────────────────────────────────

    private static let libraryPathKey = "libraryPath"

    private static func storedLibraryPath() -> String? {
        UserDefaults.standard.string(forKey: libraryPathKey)
    }

    private static func storeLibraryPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: libraryPathKey)
    }

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
