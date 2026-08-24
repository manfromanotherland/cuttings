// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class IngestionPayloadTests: XCTestCase {
    func testTrimmedHTTPTextBecomesLink() throws {
        XCTAssertEqual(
            IngestionPayloadDecoder.payload(forPlainText: "  https://example.com/a?b=1\n"),
            try .link(XCTUnwrap(URL(string: "https://example.com/a?b=1")))
        )
    }

    func testTextContainingMoreThanAURLRemainsText() {
        let string = "See https://example.com for details"
        XCTAssertEqual(IngestionPayloadDecoder.payload(forPlainText: string), .text(string))
    }

    func testNonHTTPURLRemainsText() {
        let string = "file:///tmp/private.txt"
        XCTAssertEqual(IngestionPayloadDecoder.payload(forPlainText: string), .text(string))
    }

    func testEmptyAndOversizedPlainTextAreRejected() {
        XCTAssertNil(IngestionPayloadDecoder.payload(forPlainText: " \n\t "))
        XCTAssertNil(
            IngestionPayloadDecoder.payload(forPlainText: "12345", maximumByteCount: 4)
        )
    }

    func testMarkdownAndTextFilesStayDistinct() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let markdownURL = directory.appendingPathComponent("Thoughts.md")
        let textURL = directory.appendingPathComponent("Quote.txt")
        try Data("# Heading".utf8).write(to: markdownURL)
        try Data("A line".utf8).write(to: textURL)

        XCTAssertEqual(
            IngestionPayloadDecoder.payload(forLocalFile: markdownURL),
            .markdownFile(data: Data("# Heading".utf8), suggestedFilename: "Thoughts.md")
        )
        XCTAssertEqual(
            IngestionPayloadDecoder.payload(forLocalFile: textURL),
            .textFile(data: Data("A line".utf8), suggestedFilename: "Quote.txt")
        )
    }

    func testNonUTF8AndOversizedFilesAreRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalidURL = directory.appendingPathComponent("invalid.txt")
        let oversizedURL = directory.appendingPathComponent("large.md")
        try Data([0xFF, 0xFE]).write(to: invalidURL)
        try Data("12345".utf8).write(to: oversizedURL)

        XCTAssertNil(IngestionPayloadDecoder.payload(forLocalFile: invalidURL))
        XCTAssertNil(
            IngestionPayloadDecoder.payload(forLocalFile: oversizedURL, maximumByteCount: 4)
        )
    }

    func testImageBytesAndDetectedMimeTypeArePreserved() throws {
        let jpeg = try makeJPEGData()

        XCTAssertEqual(
            IngestionPayloadDecoder.payload(
                forImageData: jpeg,
                suggestedFilename: "Photo.jpg"
            ),
            .image(data: jpeg, contentType: "image/jpeg", suggestedFilename: "Photo.jpg")
        )
        XCTAssertNil(
            IngestionPayloadDecoder.payload(
                forImageData: jpeg,
                suggestedFilename: nil,
                maximumByteCount: 4
            )
        )
        XCTAssertNil(
            IngestionPayloadDecoder.payload(
                forImageData: Data("not an image".utf8),
                suggestedFilename: nil
            )
        )
    }

    func testLocalImagePreservesOriginalBytesAndMimeType() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let jpeg = try makeJPEGData()
        let imageURL = directory.appendingPathComponent("Photo.jpg")
        try jpeg.write(to: imageURL)

        XCTAssertEqual(
            IngestionPayloadDecoder.payload(forLocalFile: imageURL),
            .image(data: jpeg, contentType: "image/jpeg", suggestedFilename: "Photo.jpg")
        )
    }

    @MainActor
    func testProviderPrecedencePrefersImageOverText() async throws {
        let provider = NSItemProvider()
        let jpeg = try makeJPEGData()
        provider.suggestedName = "Clipboard image"
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data("lower priority".utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.jpeg.identifier,
            visibility: .all
        ) { completion in
            completion(jpeg, nil)
            return nil
        }

        let payload = await IngestionItemProviderLoader.load(from: provider)
        guard case let .image(data, contentType, filename) = payload else {
            return XCTFail("expected the image representation")
        }
        XCTAssertEqual(filename, "Clipboard image")
        XCTAssertEqual(contentType, "image/jpeg")
        XCTAssertEqual(data, jpeg)
    }

    @MainActor
    func testLocalFileTakesPrecedenceOverInlineRepresentations() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("Notes.md")
        try Data("from file".utf8).write(to: fileURL)

        let provider = dataProvider(type: .fileURL, data: fileURL.dataRepresentation)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data("inline fallback".utf8), nil)
            return nil
        }

        let payload = await IngestionItemProviderLoader.load(from: provider)
        XCTAssertEqual(
            payload,
            .markdownFile(data: Data("from file".utf8), suggestedFilename: "Notes.md")
        )
    }

    @MainActor
    func testExplicitWebURLTakesPrecedenceOverPlainText() async throws {
        let expectedURL = try XCTUnwrap(URL(string: "https://example.com/explicit"))
        let provider = dataProvider(type: .url, data: expectedURL.dataRepresentation)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data("lower priority".utf8), nil)
            return nil
        }

        let payload = await IngestionItemProviderLoader.load(from: provider)
        XCTAssertEqual(payload, .link(expectedURL))
    }

    @MainActor
    func testBadProviderDoesNotDiscardValidSiblingsAndOrderIsPreserved() async {
        let invalid = dataProvider(type: .plainText, data: Data([0xFF]))
        let first = dataProvider(type: .plainText, data: Data("first".utf8))
        let second = dataProvider(type: .plainText, data: Data("second".utf8))

        let payloads = await IngestionItemProviderLoader.load(from: [invalid, first, second])

        XCTAssertEqual(payloads, [.text("first"), .text("second")])
    }

    @MainActor
    func testMalformedImageFallsThroughToPlainText() async {
        let provider = dataProvider(type: .png, data: Data("not an image".utf8))
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data("fallback".utf8), nil)
            return nil
        }

        let payload = await IngestionItemProviderLoader.load(from: provider)
        XCTAssertEqual(payload, .text("fallback"))
    }

    private func dataProvider(type: UTType, data: Data) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingestion-payload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeJPEGData() throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))

        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        try CGImageDestinationAddImage(destination, XCTUnwrap(context.makeImage()), nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}
