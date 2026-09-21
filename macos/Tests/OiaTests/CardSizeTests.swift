// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class CardSizeTests: XCTestCase {
    func testPinchZoomUsesDiscreteCardSizeSteps() {
        XCTAssertEqual(CardSize.small.zoomed(by: 1.19), .small)
        XCTAssertEqual(CardSize.small.zoomed(by: 1.2), .medium)
        XCTAssertEqual(CardSize.large.zoomed(by: 0.8), .medium)
    }

    func testLargePinchCanCrossSeveralStepsAndClamps() {
        XCTAssertEqual(CardSize.extraSmall.zoomed(by: 1.2 * 1.2 * 1.2), .large)
        XCTAssertEqual(CardSize.small.zoomed(by: 100), .extraLarge)
        XCTAssertEqual(CardSize.large.zoomed(by: 0.001), .extraSmall)
    }

    func testInvalidMagnificationKeepsCurrentSize() {
        XCTAssertEqual(CardSize.medium.zoomed(by: 0), .medium)
        XCTAssertEqual(CardSize.medium.zoomed(by: -.infinity), .medium)
        XCTAssertEqual(CardSize.medium.zoomed(by: .nan), .medium)
    }
}
