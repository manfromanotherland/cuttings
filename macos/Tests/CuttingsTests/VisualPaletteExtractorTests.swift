// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import XCTest

final class VisualPaletteExtractorTests: XCTestCase {
    func testWeightedPaletteUnpremultipliesSaturatedClusterCentres() throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let blueColor = try XCTUnwrap(CGColor(
            colorSpace: colorSpace,
            components: [0, 0, 1, 1]
        ))
        let redColor = try XCTUnwrap(CGColor(
            colorSpace: colorSpace,
            components: [1, 0, 0, 1]
        ))
        let image = try makeImage(width: 100, height: 100) { context in
            context.setFillColor(blueColor)
            context.fill(CGRect(x: 0, y: 0, width: 75, height: 100))
            context.setFillColor(redColor)
            context.fill(CGRect(x: 75, y: 0, width: 25, height: 100))
        }

        let clusters = try VisualPaletteExtractor.clusters(from: image)
        let blue = try XCTUnwrap(clusters.first {
            $0.blue > 0.9 && $0.red < 0.1 && $0.green < 0.1
        })
        let red = try XCTUnwrap(clusters.first {
            $0.red > 0.9 && $0.green < 0.1 && $0.blue < 0.1
        })

        XCTAssertEqual(blue.weight, 0.75, accuracy: 0.03)
        XCTAssertEqual(red.weight, 0.25, accuracy: 0.03)
        XCTAssertEqual(clusters.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.000_001)
    }

    func testFixedMeansProduceARepeatablePalette() throws {
        let image = try makeImage(width: 32, height: 16) { context in
            context.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 0.85, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
        }

        let first = try VisualPaletteExtractor.clusters(from: image)
        let second = try VisualPaletteExtractor.clusters(from: image)

        XCTAssertEqual(first.count, second.count)
        for (lhs, rhs) in zip(first, second) {
            XCTAssertEqual(lhs.red, rhs.red, accuracy: 0.001)
            XCTAssertEqual(lhs.green, rhs.green, accuracy: 0.001)
            XCTAssertEqual(lhs.blue, rhs.blue, accuracy: 0.001)
            XCTAssertEqual(lhs.weight, rhs.weight, accuracy: 0.001)
        }
    }

    func testTransparentPixelsUseTheFixedWhiteBackground() throws {
        let image = try makeImage(width: 16, height: 16) { context in
            context.clear(CGRect(x: 0, y: 0, width: 16, height: 16))
        }

        let clusters = try VisualPaletteExtractor.clusters(from: image)
        let white = try XCTUnwrap(clusters.first {
            $0.red > 0.95 && $0.green > 0.95 && $0.blue > 0.95
        })
        XCTAssertEqual(white.weight, 1, accuracy: 0.01)
    }

    func testOnlyUnsupportedSourceBytesArePermanent() {
        let url = URL(fileURLWithPath: "/tmp/image.dat")

        XCTAssertTrue(VisualAnalysisError.unsupportedImage(url).isPermanentlyUnsupported)
        XCTAssertFalse(VisualAnalysisError.unreadableImage(url).isPermanentlyUnsupported)
        XCTAssertFalse(VisualAnalysisError.imageNormalizationFailed.isPermanentlyUnsupported)
        XCTAssertFalse(
            VisualAnalysisError.classificationProducedNoResults.isPermanentlyUnsupported
        )
        XCTAssertFalse(VisualAnalysisError.paletteExtractionFailed.isPermanentlyUnsupported)
    }

    private func makeImage(
        width: Int,
        height: Int,
        draw: (CGContext) -> Void
    ) throws -> CGImage {
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
        draw(context)
        return try XCTUnwrap(context.makeImage())
    }
}
