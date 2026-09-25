// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CryptoKit
import ImageIO
import SQLite3
import XCTest

/// Seed the disposable analysis cache, just as a previous local analysis pass
/// would. UI tests must never donate fixture IDs to the user's Spotlight index.
enum InspectorAnalysisFixture {
    static func png(color: NSColor) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func seed(dbURL: URL, image: Data, color: NSColor) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let hash = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        let palette = """
        [{"red":\(rgb.redComponent),"green":\(rgb.greenComponent),"blue":\(rgb.blueComponent),"weight":1}]
        """
        let sql = """
        INSERT OR REPLACE INTO visual_analysis
        (content_hash, analyzer_version, supported, labels_json, palette_json, visual_terms, completed_at)
        VALUES (?, 'inspector-ui-fixture', 1, '[{"identifier":"cabinet","confidence":0.9}]', ?, 'cabinet', '2026-09-25')
        """
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        XCTAssertEqual(sqlite3_bind_text(statement, 1, hash, -1, transient), SQLITE_OK)
        XCTAssertEqual(sqlite3_bind_text(statement, 2, palette, -1, transient), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }
}
