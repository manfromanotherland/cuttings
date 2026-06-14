// SPDX-License-Identifier: GPL-3.0-or-later

// Thin wrapper around the UniFFI-generated `Database` object.
// All calls are dispatched to a background actor so the UI stays responsive.

import Foundation
import ReadLaterCore

actor CoreBridge {
    private let db: Database
    private let libraryPath: String

    init(libraryPath: String, dbPath: String) throws {
        self.libraryPath = libraryPath
        self.db = try Database.open(dbPath: dbPath)
    }

    // ── Indexing ──────────────────────────────────────────────────────────

    func rebuild() throws {
        try db.rebuild(libraryPath: libraryPath)
    }

    @discardableResult
    func sync() throws -> UInt32 {
        try db.sync(libraryPath: libraryPath)
    }

    // ── Query ─────────────────────────────────────────────────────────────

    func search(query: String, limit: UInt32 = 20) throws -> [FfiSearchResult] {
        try db.search(query: query, limit: limit)
    }

    func listReadings(opts: FfiListOptions) throws -> [FfiReadingRow] {
        try db.listReadings(opts: opts)
    }

    func getReadingRow(id: String) throws -> FfiReadingRow? {
        try db.getReadingRow(id: id)
    }

    func getBody(id: String) throws -> String? {
        try db.getBody(id: id)
    }

    // ── Tags ──────────────────────────────────────────────────────────────

    func listTags() throws -> [FfiTagCount] {
        try db.listTags()
    }

    func addTag(id: String, tag: String) throws {
        try db.addTag(libraryPath: libraryPath, id: id, tag: tag)
    }

    func removeTag(id: String, tag: String) throws {
        try db.removeTag(libraryPath: libraryPath, id: id, tag: tag)
    }

    // ── Status flags ──────────────────────────────────────────────────────

    func setRead(id: String, read: Bool) throws {
        try db.setRead(libraryPath: libraryPath, id: id, read: read)
    }

    func setArchived(id: String, archived: Bool) throws {
        try db.setArchived(libraryPath: libraryPath, id: id, archived: archived)
    }

    func setFavorite(id: String, favorite: Bool) throws {
        try db.setFavorite(libraryPath: libraryPath, id: id, favorite: favorite)
    }
}
