// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import XCTest

final class VideoCardViewportTests: XCTestCase {
    private let viewport = CGRect(x: 20, y: 40, width: 800, height: 600)

    func testCardIsVisibleWhenItIntersectsViewport() {
        XCTAssertTrue(
            VideoCardViewport.containsVisibleArea(
                of: CGRect(x: 100, y: 100, width: 200, height: 150),
                in: viewport
            )
        )
        XCTAssertTrue(
            VideoCardViewport.containsVisibleArea(
                of: CGRect(x: 100, y: 630, width: 200, height: 150),
                in: viewport
            )
        )
    }

    func testCardIsNotVisibleOutsideOrTouchingViewportEdge() {
        XCTAssertFalse(
            VideoCardViewport.containsVisibleArea(
                of: CGRect(x: 100, y: 700, width: 200, height: 150),
                in: viewport
            )
        )
        XCTAssertFalse(
            VideoCardViewport.containsVisibleArea(
                of: CGRect(x: 100, y: 640, width: 200, height: 150),
                in: viewport
            )
        )
    }

    func testInvalidGeometryIsNotVisible() {
        XCTAssertFalse(
            VideoCardViewport.containsVisibleArea(of: .zero, in: viewport)
        )
        XCTAssertFalse(
            VideoCardViewport.containsVisibleArea(
                of: CGRect(x: CGFloat.nan, y: 0, width: 200, height: 150),
                in: viewport
            )
        )
    }
}
