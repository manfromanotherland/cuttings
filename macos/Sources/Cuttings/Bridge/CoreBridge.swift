// SPDX-License-Identifier: GPL-3.0-or-later

// Thin wrapper around the UniFFI-generated `Database` object.
// All calls are dispatched to a background actor so the UI stays responsive.

import Foundation

actor CoreBridge {
    private let database: Database
    private let libraryPath: String

    init(libraryPath: String, dbPath: String) throws {
        self.libraryPath = libraryPath
        database = try Database.open(dbPath: dbPath)
    }

    // ── Indexing ──────────────────────────────────────────────────────────

    func rebuild() throws {
        try database.rebuild(libraryPath: libraryPath)
    }

    @discardableResult
    func sync() throws -> UInt32 {
        try database.sync(libraryPath: libraryPath)
    }

    func pendingVisualAnalysis(
        analyzerVersion: String, limit: UInt32
    ) throws -> [VisualAnalysisWorkItem] {
        try database.pendingVisualAnalysis(
            libraryPath: libraryPath,
            analyzerVersion: analyzerVersion,
            limit: limit
        ).map(VisualAnalysisWorkItem.init)
    }

    @discardableResult
    func completeVisualAnalysis(
        task: VisualAnalysisWorkItem, result: VisualAnalysisCompletion
    ) throws -> Bool {
        try database.completeVisualAnalysis(
            libraryPath: libraryPath,
            task: task.ffi,
            result: result.ffi
        )
    }

    func currentVisualAssets() throws -> [VisualAssetSnapshot] {
        try database.currentVisualAssets(libraryPath: libraryPath).map(VisualAssetSnapshot.init)
    }

    // ── Query ─────────────────────────────────────────────────────────────

    /// One page of readings for the composed scope/tag filter, the board order,
    /// and an optional full-text query. Dormant rating support remains nil at the
    /// FFI boundary for library-format compatibility.
    func listReadings(_ query: ReadingQuery) throws -> [FfiReadingRow] {
        let opts = FfiListOptions(
            view: query.scope.ffiView,
            sort: query.sort.ffiSort,
            ascending: query.ascending,
            tag: query.tag,
            rating: nil,
            kind: query.kind?.ffiKind,
            since: nil, until: nil,
            query: query.search,
            predominantColor: nil,
            semanticCandidateIds: query.semanticCandidateIDs,
            limit: query.limit, offset: query.offset
        )
        return try database.listReadings(opts: opts)
    }

    /// Reuse the compatible count payload to enumerate tags for the app's filter
    /// menu. Legacy view and rating counts remain dormant at the FFI boundary.
    func filterCounts(
        kind: ReadingKind?, scope: LibraryScope, tag: String?, query: String?
    ) throws -> FfiSidebarCounts {
        let ffiScope = FfiCountScope(
            view: scope.ffiView,
            tag: tag,
            rating: nil,
            kind: kind?.ffiKind,
            query: query,
            predominantColor: nil,
            semanticCandidateIds: []
        )
        return try database.sidebarCounts(scope: ffiScope)
    }

    func getReadingRow(id: String) throws -> FfiReadingRow? {
        try database.getReadingRow(id: id)
    }

    func getBody(id: String) throws -> String? {
        try database.getBody(id: id)
    }

    // ── Imports ───────────────────────────────────────────────────────────

    func importLink(url: String) throws -> FfiImportResult {
        try database.importLink(libraryPath: libraryPath, url: url)
    }

    func importText(text: String, title: String?) throws -> FfiImportResult {
        try database.importText(libraryPath: libraryPath, text: text, title: title)
    }

    func importImage(data: Data, contentType: String, title: String) throws -> FfiImportResult {
        try database.importImage(
            libraryPath: libraryPath,
            bytes: data,
            contentType: contentType,
            title: title
        )
    }

    /// The staged movie stays file-backed across the FFI boundary so large
    /// videos are never copied into a Swift or UniFFI byte buffer.
    func importVideoFile(
        filePath: String, contentType: String, title: String
    ) throws -> FfiImportResult {
        try database.importVideoFile(
            libraryPath: libraryPath,
            filePath: filePath,
            contentType: contentType,
            title: title
        )
    }

    // ── Tags ──────────────────────────────────────────────────────────────

    func addTag(id: String, tag: String) throws {
        try database.addTag(libraryPath: libraryPath, id: id, tag: tag)
    }

    func removeTag(id: String, tag: String) throws {
        try database.removeTag(libraryPath: libraryPath, id: id, tag: tag)
    }

    // ── Deletion ──────────────────────────────────────────────────────────

    /// Permanently delete a reading (file, assets, and index row).
    func deleteReading(id: String) throws {
        try database.deleteReading(libraryPath: libraryPath, id: id)
    }

    // ── Highlights ────────────────────────────────────────────────────────

    func listHighlights(readingId: String) throws -> [FfiHighlight] {
        try database.listHighlights(libraryPath: libraryPath, readingId: readingId)
    }

    @discardableResult
    func addHighlight(readingId: String, text: String) throws -> FfiHighlight {
        try database.addHighlight(libraryPath: libraryPath, readingId: readingId, text: text)
    }

    /// Toggle a highlight by its text. Returns `true` if highlighted after the
    /// call, `false` if it was cleared.
    @discardableResult
    func toggleHighlight(readingId: String, text: String) throws -> Bool {
        try database.toggleHighlight(libraryPath: libraryPath, readingId: readingId, text: text)
    }

    func deleteHighlight(readingId: String, highlightId: String) throws {
        try database.deleteHighlight(libraryPath: libraryPath, readingId: readingId, highlightId: highlightId)
    }
}
