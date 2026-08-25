// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class SpotlightThumbnailRendererTests: XCTestCase {
    func testRendererAppliesOrientationAndPixelBound() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceURL = root.appendingPathComponent("oriented.jpg")
        let destinationURL = root.appendingPathComponent("thumbnail.png")
        try writeJPEG(
            try makeSolidImage(width: 400, height: 200),
            to: sourceURL,
            orientation: 6
        )

        try SpotlightThumbnailRenderer.writeThumbnail(
            from: sourceURL,
            to: destinationURL,
            maximumPixelDimension: 100
        )

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(destinationURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 50)
        XCTAssertEqual(image.height, 100)
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testValidThumbnailSurvivesAlongsideCorruptSource() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let validSource = root.appendingPathComponent("valid.png")
        let corruptSource = root.appendingPathComponent("corrupt.png")
        let validDestination = root.appendingPathComponent("valid-thumbnail.png")
        let corruptDestination = root.appendingPathComponent("corrupt-thumbnail.png")
        let validData = try SpotlightThumbnailRenderer.pngData(
            from: makeSolidImage(width: 20, height: 10)
        )
        try validData.write(to: validSource, options: .atomic)
        try Data("not an image".utf8).write(to: corruptSource, options: .atomic)

        try SpotlightThumbnailRenderer.writeThumbnail(
            from: validSource,
            to: validDestination,
            maximumPixelDimension: 100
        )
        XCTAssertThrowsError(try SpotlightThumbnailRenderer.writeThumbnail(
            from: corruptSource,
            to: corruptDestination,
            maximumPixelDimension: 100
        )) { error in
            guard let analysisError = error as? VisualAnalysisError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(analysisError.isPermanentlyUnsupported)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: validDestination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptDestination.path))
    }

    private func makeTemporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cuttings-spotlight-renderer-\(UUID().uuidString)")
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func writeJPEG(
        _ image: CGImage,
        to url: URL,
        orientation: Int
    ) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let properties = [kCGImagePropertyOrientation: orientation] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
