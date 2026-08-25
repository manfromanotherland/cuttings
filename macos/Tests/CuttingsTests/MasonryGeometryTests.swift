// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class MasonryGeometryTests: XCTestCase {
    func testSmallCardSizePreservesExistingColumnWidth() {
        XCTAssertEqual(CardSize.small.minimumColumnWidth, 220)
    }

    func testCardSizesProduceIncreasingColumnWidths() {
        XCTAssertLessThan(
            CardSize.extraSmall.minimumColumnWidth, CardSize.small.minimumColumnWidth
        )
        XCTAssertLessThan(CardSize.small.minimumColumnWidth, CardSize.medium.minimumColumnWidth)
        XCTAssertLessThan(CardSize.medium.minimumColumnWidth, CardSize.large.minimumColumnWidth)
        XCTAssertLessThan(
            CardSize.large.minimumColumnWidth, CardSize.extraLarge.minimumColumnWidth
        )
    }

    func testFiveCardSizesProduceDistinctDefaultWindowDensities() {
        let columnCounts = CardSize.allCases.map { size in
            MasonryGeometry.columnCount(
                width: 1_064,
                minimumColumnWidth: size.minimumColumnWidth,
                spacing: 18,
                maximum: 6
            )
        }

        XCTAssertEqual(columnCounts, [5, 4, 3, 2, 1])
    }

    func testFiveCardSizesRemainDistinctOnWideBoard() {
        let width: CGFloat = 2_524
        let renderedWidths = CardSize.allCases.map { size in
            let columns = MasonryGeometry.columnCount(
                width: width,
                minimumColumnWidth: size.minimumColumnWidth,
                spacing: 18,
                maximum: MasonryLayout().maximumColumns
            )
            return MasonryGeometry.columnWidth(
                width: width,
                columns: columns,
                spacing: 18
            )
        }

        for (smaller, larger) in zip(renderedWidths, renderedWidths.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }
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

    func testCardSizesStepInPersistedSizeOrder() {
        XCTAssertEqual(
            CardSize.allCases,
            [.extraSmall, .small, .medium, .large, .extraLarge]
        )
        XCTAssertEqual(
            CardSize.allCases.map(\.rawValue),
            ["extraSmall", "small", "medium", "large", "extraLarge"]
        )
        XCTAssertNil(CardSize.extraSmall.smaller)
        XCTAssertEqual(CardSize.extraSmall.larger, .small)
        XCTAssertEqual(CardSize.small.smaller, .extraSmall)
        XCTAssertEqual(CardSize.small.larger, .medium)
        XCTAssertEqual(CardSize.medium.smaller, .small)
        XCTAssertEqual(CardSize.medium.larger, .large)
        XCTAssertEqual(CardSize.large.smaller, .medium)
        XCTAssertEqual(CardSize.large.larger, .extraLarge)
        XCTAssertEqual(CardSize.extraLarge.smaller, .large)
        XCTAssertNil(CardSize.extraLarge.larger)
    }
}
