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
    }

    func testOptionalFieldsPreserveNil() {
        let ffi = FfiReadingRow(
            id: "01JREADING000000000000000001",
            title: "",
            kind: .article,
            lightweight: false,
            hasNote: false,
            url: "https://example.com/b",
            mediaUrl: nil,
            previewAsset: nil,
            canonicalUrl: "https://example.com/b",
            author: nil,
            site: nil,
            savedAt: "2026-01-01T00:00:00Z",
            read: false,
            archived: false,
            favorite: false,
            rating: 0,
            excerpt: nil,
            wordCount: nil,
            lang: nil,
            tags: []
        )
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
