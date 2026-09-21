// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest

final class AssetPreviewLoadPlanTests: XCTestCase {
    func testScrollingBoardCardRequestsOnlyLightweightPreview() {
        let plan = AssetPreviewLoadPlan(
            maxPixel: 800,
            loadsProgressively: true,
            isVisible: true,
            isScrolling: true
        )

        XCTAssertEqual(plan.initialMaxPixel, 160)
        XCTAssertNil(plan.refinementMaxPixel)
    }

    func testIdleBoardCardStagesDisplayQualityAfterLightweightPreview() {
        let plan = AssetPreviewLoadPlan(
            maxPixel: 800,
            loadsProgressively: true,
            isVisible: true,
            isScrolling: false
        )

        XCTAssertEqual(plan.initialMaxPixel, 160)
        XCTAssertEqual(plan.refinementMaxPixel, 800)
    }

    func testOffscreenOverscanCardDoesNotRequestAnImage() {
        let plan = AssetPreviewLoadPlan(
            maxPixel: 800,
            loadsProgressively: true,
            isVisible: false,
            isScrolling: true
        )

        XCTAssertNil(plan.initialMaxPixel)
        XCTAssertNil(plan.refinementMaxPixel)
    }

    func testDetailImageKeepsImmediateDisplayQualityDecode() {
        let plan = AssetPreviewLoadPlan(
            maxPixel: 1600,
            loadsProgressively: false,
            isVisible: true,
            isScrolling: false
        )

        XCTAssertEqual(plan.initialMaxPixel, 1600)
        XCTAssertNil(plan.refinementMaxPixel)
    }

    func testDisplayQualityTracksActualRenderedBackingSize() {
        XCTAssertEqual(
            AssetPreviewLoadPlan.displayMaxPixel(
                for: CGSize(width: 202.5, height: 337.25), displayScale: 2
            ),
            675
        )
        XCTAssertEqual(
            AssetPreviewLoadPlan.displayMaxPixel(
                for: CGSize(width: 700, height: 900), displayScale: 2
            ),
            1024
        )
        XCTAssertEqual(
            AssetPreviewLoadPlan.displayMaxPixel(
                for: CGSize(width: 300, height: 100), displayScale: .nan
            ),
            300
        )
        XCTAssertEqual(
            AssetPreviewLoadPlan.displayMaxPixel(
                for: CGSize(width: 300, height: 30000), displayScale: 2
            ),
            1024
        )
    }

    @MainActor
    func testDecodedPreviewCacheKeepsRequestedPixelVariantsSeparate() throws {
        let cache = AssetPreviewImageCache(countLimit: 4, totalCostLimit: 10_000_000)
        let url = URL(fileURLWithPath: "/tmp/oia-preview-cache-test.png")
        let lightweight = NSImage(size: NSSize(width: 160, height: 100))
        let display = NSImage(size: NSSize(width: 800, height: 500))
        let lightweightKey = AssetPreviewDecodeKey(
            kind: .image, url: url, maxPixel: 160
        )
        let displayKey = AssetPreviewDecodeKey(
            kind: .image, url: url, maxPixel: 800
        )

        cache.insert(lightweight, for: lightweightKey)
        XCTAssertTrue(try XCTUnwrap(cache.entry(for: lightweightKey)).image === lightweight)
        XCTAssertNil(cache.entry(for: displayKey))

        cache.insert(display, for: displayKey)
        XCTAssertTrue(try XCTUnwrap(cache.entry(for: displayKey)).image === display)
        XCTAssertTrue(try XCTUnwrap(cache.entry(for: lightweightKey)).image === lightweight)
    }

    @MainActor
    func testPresentationDropsEveryVariantWhenAssetIdentityChanges() {
        let firstURL = URL(fileURLWithPath: "/tmp/first-preview.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second-preview.png")
        let image = NSImage(size: NSSize(width: 800, height: 500))
        var presentation = AssetPreviewPresentation()

        presentation.publish(
            AssetPreviewVariant(image: image, decodedForMaxPixel: 800),
            quality: .display,
            for: firstURL
        )
        presentation.reset(for: secondURL)

        XCTAssertEqual(presentation.requestURL, secondURL)
        XCTAssertNil(presentation.lightweight)
        XCTAssertNil(presentation.display)
        XCTAssertFalse(presentation.failed)
    }

    @MainActor
    func testPresentationKeepsLightweightImageSelectedDuringScrolling() throws {
        let url = URL(fileURLWithPath: "/tmp/tiered-preview.png")
        let lightweight = NSImage(size: NSSize(width: 160, height: 100))
        let display = NSImage(size: NSSize(width: 800, height: 500))
        var presentation = AssetPreviewPresentation()

        presentation.publish(
            AssetPreviewVariant(image: lightweight, decodedForMaxPixel: 160),
            quality: .lightweight,
            for: url
        )
        presentation.publish(
            AssetPreviewVariant(image: display, decodedForMaxPixel: 800),
            quality: .display,
            for: url
        )

        XCTAssertTrue(try XCTUnwrap(presentation.variant(
            for: .lightweight,
            requestURL: url,
            isVisible: true
        )).image === lightweight)
        XCTAssertTrue(try XCTUnwrap(presentation.variant(
            for: .display,
            requestURL: url,
            isVisible: true
        )).image === display)
    }
}
