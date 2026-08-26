// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class ReadingRowMediaGeometryTests: XCTestCase {
    func testPortraitImageHeightPreservesIntrinsicAspectRatio() throws {
        let aspectRatio = 1900.0 / 2468.0
        let row = makeReadingRow(kind: .image, mediaAspectRatio: aspectRatio)

        let height = try XCTUnwrap(row.standaloneMediaHeight(for: 380))

        XCTAssertEqual(height, 380 / CGFloat(aspectRatio), accuracy: 0.0001)
    }

    func testLandscapeVideoHeightPreservesIntrinsicAspectRatio() throws {
        let aspectRatio = 21.0 / 9.0
        let row = makeReadingRow(kind: .video, mediaAspectRatio: aspectRatio)

        let height = try XCTUnwrap(row.standaloneMediaHeight(for: 420))

        XCTAssertEqual(height, 420 / CGFloat(aspectRatio), accuracy: 0.0001)
    }

    func testStandaloneMediaUsesStableFallbackRatiosWhenMetadataIsUnavailable() {
        let image = makeReadingRow(kind: .image)
        let video = makeReadingRow(kind: .video)

        XCTAssertEqual(image.standaloneMediaAspectRatio, 4.0 / 3.0)
        XCTAssertEqual(video.standaloneMediaAspectRatio, 16.0 / 9.0)
    }

    func testArticlePreviewUsesStandardSocialAspectRatio() throws {
        let row = makeReadingRow(kind: .article, previewAsset: "assets/social.jpg")

        let height = try XCTUnwrap(row.articlePreviewHeight(for: 400))

        XCTAssertEqual(row.articlePreviewAspectRatio, ReadingRow.socialPreviewAspectRatio)
        XCTAssertEqual(
            height,
            400 / ReadingRow.socialPreviewAspectRatio,
            accuracy: 0.0001
        )
    }

    func testArticlePreviewUsesIndexedRatioWhenAvailable() throws {
        let aspectRatio = 2.0
        let row = makeReadingRow(
            kind: .article,
            previewAsset: "assets/social.jpg",
            mediaAspectRatio: aspectRatio
        )

        XCTAssertEqual(row.articlePreviewAspectRatio, CGFloat(aspectRatio))
        XCTAssertEqual(try XCTUnwrap(row.articlePreviewHeight(for: 400)), 200)
    }

    func testInvalidIndexedRatiosUseStableFallbacks() {
        let invalidRatios = [Double.nan, .infinity, 0, -1]

        for aspectRatio in invalidRatios {
            let image = makeReadingRow(kind: .image, mediaAspectRatio: aspectRatio)
            let article = makeReadingRow(
                kind: .article,
                previewAsset: "assets/social.jpg",
                mediaAspectRatio: aspectRatio
            )
            XCTAssertEqual(image.standaloneMediaAspectRatio, 4.0 / 3.0)
            XCTAssertEqual(article.articlePreviewAspectRatio, ReadingRow.socialPreviewAspectRatio)
        }
    }

    func testArticleAndQuoteNeverUseStandaloneMediaGeometry() {
        let article = makeReadingRow(kind: .article, mediaAspectRatio: 2)
        let quote = makeReadingRow(kind: .quote, mediaAspectRatio: 2)

        XCTAssertNil(article.articlePreviewAspectRatio)
        XCTAssertNil(article.articlePreviewHeight(for: 320))
        XCTAssertNil(article.standaloneMediaAspectRatio)
        XCTAssertNil(article.standaloneMediaHeight(for: 320))
        XCTAssertNil(quote.articlePreviewAspectRatio)
        XCTAssertNil(quote.articlePreviewHeight(for: 320))
        XCTAssertNil(quote.standaloneMediaAspectRatio)
        XCTAssertNil(quote.standaloneMediaHeight(for: 320))
    }
}
