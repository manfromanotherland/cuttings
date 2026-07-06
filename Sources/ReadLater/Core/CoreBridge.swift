// SPDX-License-Identifier: GPL-3.0-or-later

// Thin wrapper around the UniFFI-generated `Database` object.
// All calls are dispatched to a background actor so the UI stays responsive.

import Foundation

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

    func listReadings(opts: FfiListOptions) throws -> [FfiReadingRow] {
        try db.listReadings(opts: opts)
    }

    /// Per-view counts in one pass — replaces five
    /// `listReadings(limit: 9999).count` calls.
    func viewCounts() throws -> FfiViewCounts {
        try db.viewCounts()
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

    // ── Ratings ───────────────────────────────────────────────────────────

    /// Set a reading's star rating (0–5, where 0 clears it).
    func setRating(id: String, rating: UInt8) throws {
        try db.setRating(libraryPath: libraryPath, id: id, rating: rating)
    }

    func listRatings() throws -> [FfiRatingCount] {
        try db.listRatings()
    }

    // ── Deletion ──────────────────────────────────────────────────────────

    /// Permanently delete a reading (file, assets, and index row).
    func deleteReading(id: String) throws {
        try db.deleteReading(libraryPath: libraryPath, id: id)
    }

    // ── Highlights ────────────────────────────────────────────────────────

    func listHighlights(readingId: String) throws -> [FfiHighlight] {
        try db.listHighlights(libraryPath: libraryPath, readingId: readingId)
    }

    @discardableResult
    func addHighlight(readingId: String, text: String) throws -> FfiHighlight {
        try db.addHighlight(libraryPath: libraryPath, readingId: readingId, text: text)
    }

    /// Toggle a highlight by its text. Returns `true` if highlighted after the
    /// call, `false` if it was cleared.
    @discardableResult
    func toggleHighlight(readingId: String, text: String) throws -> Bool {
        try db.toggleHighlight(libraryPath: libraryPath, readingId: readingId, text: text)
    }

    func deleteHighlight(readingId: String, highlightId: String) throws {
        try db.deleteHighlight(libraryPath: libraryPath, readingId: readingId, highlightId: highlightId)
    }
}
