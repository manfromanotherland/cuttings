// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class MasonryCardHeightLoaderTests: XCTestCase {
    func testPrecomputesEveryRequestedWidthAndUsesMediaAspectRatio() async {
        var image = makeReadingRow(kind: .image)
        image.id = "image"
        image.previewAsset = "assets/image.jpg"

        var article = makeReadingRow()
        article.id = "article"
        article.title = "A title that wraps differently as card density changes"
        article.excerpt = "A deterministic excerpt used to exercise the text-height cache."

        let widths: [CGFloat] = [180, 220, 300, 400, 540]
        let heights = await MasonryCardHeightLoader.shared.heights(
            for: [image, article],
            aspectRatios: [image.id: 2],
            widths: widths
        )

        XCTAssertEqual(heights.count, widths.count * 2)
        for width in widths {
            XCTAssertEqual(
                heights[MasonryCardHeightKey(readingID: image.id, width: width)],
                ceil(width / 2)
            )
            XCTAssertGreaterThan(
                heights[MasonryCardHeightKey(readingID: article.id, width: width)] ?? 0,
                0
            )
        }
    }

    func testGeometryIdentityChangesWhenSameIDContentChanges() {
        var original = makeReadingRow()
        let originalIdentity = MasonryCardGeometryIdentity(row: original)

        original.title = "Externally edited title"
        XCTAssertNotEqual(originalIdentity, MasonryCardGeometryIdentity(row: original))

        original.previewAsset = "assets/captured.jpg"
        XCTAssertNotEqual(originalIdentity, MasonryCardGeometryIdentity(row: original))
    }

    func testColumnWidthsUseStableTwoPointBuckets() {
        XCTAssertEqual(MasonryColumnWidthBucket.bucket(for: 200), 100)
        XCTAssertEqual(MasonryColumnWidthBucket.bucket(for: 201.99), 100)
        XCTAssertEqual(MasonryColumnWidthBucket.bucket(for: 202), 101)
        XCTAssertEqual(MasonryColumnWidthBucket.width(for: 175), 350)
    }
}
