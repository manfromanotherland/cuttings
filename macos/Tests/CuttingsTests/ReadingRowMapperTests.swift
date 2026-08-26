// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `ReadingRow(_: FfiReadingRow)` is the single crossing from the FFI boundary
/// DTO to the presentation snapshot. These tests pin that every field carries
/// across intact, that optionals preserve nil, and that equality tracks fields.
final class ReadingRowMapperTests: XCTestCase {
    /// An FFI row with a distinct value in every field, so a miswired assignment
    /// (say `url` ← `canonicalUrl`) surfaces as a mismatch.
    private func sampleFfiRow() -> FfiReadingRow {
        FfiReadingRow(
            id: "01JREADING000000000000000000",
            title: "The Title",
            kind: .video,
            lightweight: true,
            hasNote: true,
            url: "https://example.com/article",
            mediaUrl: "https://cdn.example.com/video.mp4",
            previewAsset: "assets/poster.jpg",
            faviconAsset: "assets/favicon.ico",
            themeColor: "#123456",
            mediaAspectRatio: 16.0 / 9.0,
            canonicalUrl: "https://example.com/article?canonical",
            author: "Ada Lovelace",
            site: "example.com",
            savedAt: "2026-03-04T05:06:07Z",
            read: true,
            archived: true,
            favorite: true,
            rating: 4,
            excerpt: "A short excerpt.",
            wordCount: 1234,
            lang: "en",
            tags: ["rust", "local-first"]
        )
    }

    func testMapsEveryFieldAcross() {
        let ffi = sampleFfiRow()
        let row = ReadingRow(ffi)
        XCTAssertEqual(row.id, ffi.id)
        XCTAssertEqual(row.title, ffi.title)
        XCTAssertEqual(row.url, ffi.url)
        XCTAssertEqual(row.canonicalUrl, ffi.canonicalUrl)
        XCTAssertEqual(row.author, ffi.author)
        XCTAssertEqual(row.site, ffi.site)
        XCTAssertEqual(row.savedAt, ffi.savedAt)
        XCTAssertEqual(row.read, ffi.read)
        XCTAssertEqual(row.archived, ffi.archived)
        XCTAssertEqual(row.favorite, ffi.favorite)
        XCTAssertEqual(row.rating, ffi.rating)
        XCTAssertEqual(row.excerpt, ffi.excerpt)
        XCTAssertEqual(row.wordCount, ffi.wordCount)
        XCTAssertEqual(row.lang, ffi.lang)
        XCTAssertEqual(row.tags, ffi.tags)
        XCTAssertEqual(row.kind, .video)
        XCTAssertEqual(row.lightweight, ffi.lightweight)
        XCTAssertEqual(row.mediaUrl, ffi.mediaUrl)
        XCTAssertEqual(row.previewAsset, ffi.previewAsset)
        XCTAssertEqual(row.faviconAsset, ffi.faviconAsset)
        XCTAssertEqual(row.themeColor, ffi.themeColor)
        XCTAssertEqual(row.mediaAspectRatio, ffi.mediaAspectRatio)
    }

    func testOptionalFieldsPreserveNil() {
        var ffi = sampleFfiRow()
        ffi.kind = .article
        ffi.lightweight = false
        ffi.mediaUrl = nil
        ffi.previewAsset = nil
        ffi.faviconAsset = nil
        ffi.themeColor = nil
        ffi.mediaAspectRatio = nil
        ffi.author = nil
        ffi.site = nil
        ffi.excerpt = nil
        ffi.wordCount = nil
        ffi.lang = nil
        ffi.tags = []
        let row = ReadingRow(ffi)
        XCTAssertNil(row.author)
        XCTAssertNil(row.site)
        XCTAssertNil(row.excerpt)
        XCTAssertNil(row.wordCount)
        XCTAssertNil(row.lang)
        XCTAssertEqual(row.kind, .article)
        XCTAssertFalse(row.lightweight)
        XCTAssertNil(row.mediaUrl)
        XCTAssertNil(row.previewAsset)
        XCTAssertNil(row.faviconAsset)
        XCTAssertNil(row.themeColor)
        XCTAssertNil(row.mediaAspectRatio)
        XCTAssertTrue(row.tags.isEmpty)
    }

    func testMapsQuoteKind() {
        var ffi = sampleFfiRow()
        ffi.kind = .quote
        XCTAssertEqual(ReadingRow(ffi).kind, .quote)
    }

    func testEqualityTracksFields() {
        let base = ReadingRow(sampleFfiRow())
        XCTAssertEqual(base, ReadingRow(sampleFfiRow()))
        var favoriteFlipped = base
        favoriteFlipped.favorite.toggle()
        XCTAssertNotEqual(base, favoriteFlipped)
    }
}
