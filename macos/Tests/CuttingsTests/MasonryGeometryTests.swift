// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class MasonryGeometryTests: XCTestCase {
    func testSmallCardSizePreservesExistingColumnWidth() {
        XCTAssertEqual(CardSize.small.minimumColumnWidth, 220)
    }

    func testCardSizesProduceIncreasingColumnWidths() {
        XCTAssertLessThan(CardSize.small.minimumColumnWidth, CardSize.medium.minimumColumnWidth)
        XCTAssertLessThan(CardSize.medium.minimumColumnWidth, CardSize.large.minimumColumnWidth)
    }

    func testResolvedWidthFallsBackForUnboundedProposals() {
        for proposedWidth: CGFloat? in [nil, .infinity, -.infinity, .nan] {
            XCTAssertEqual(
                MasonryGeometry.resolvedWidth(
                    proposedWidth: proposedWidth, minimumColumnWidth: 220
                ),
                220
            )
        }
    }

    func testColumnCountRespectsAvailableWidthAndMaximum() {
        XCTAssertEqual(
            MasonryGeometry.columnCount(
                width: 900, minimumColumnWidth: 220, spacing: 18, maximum: 6
            ),
            3
        )
        XCTAssertEqual(
            MasonryGeometry.columnCount(
                width: 2000, minimumColumnWidth: 220, spacing: 18, maximum: 6
            ),
            6
        )
    }

    func testColumnCountRejectsNonFiniteWidth() {
        for width: CGFloat in [.infinity, -.infinity, .nan] {
            XCTAssertEqual(
                MasonryGeometry.columnCount(
                    width: width, minimumColumnWidth: 220, spacing: 18, maximum: 6
                ),
                1
            )
        }
    }

    func testColumnWidthAccountsForGaps() {
        XCTAssertEqual(
            MasonryGeometry.columnWidth(width: 696, columns: 3, spacing: 18),
            220,
            accuracy: 0.001
        )
    }

    func testShortestColumnPrefersFirstOnTie() {
        XCTAssertEqual(MasonryGeometry.shortestColumn(in: [120, 80, 80]), 1)
        XCTAssertEqual(MasonryGeometry.shortestColumn(in: []), 0)
    }

    func testCardSizeControlUsesRequestedIconsInSizeOrder() {
        XCTAssertEqual(CardSize.allCases, [.small, .medium, .large])
        XCTAssertEqual(CardSize.allCases.map(\.rawValue), ["small", "medium", "large"])
        XCTAssertEqual(
            CardSize.allCases.map(\.symbol),
            ["square.grid.3x3.fill", "square.grid.3x2.fill", "square.grid.2x2.fill"]
        )
    }
}
