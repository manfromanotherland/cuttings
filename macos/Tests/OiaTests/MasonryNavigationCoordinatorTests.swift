// SPDX-License-Identifier: GPL-3.0-or-later

import LazyLayoutKit
import XCTest

final class MasonryNavigationCoordinatorTests: XCTestCase {
    private let elements = [100.0, 100.0, 100.0, 100.0]
    private let ids = [0, 1, 2, 3]

    @MainActor
    func testRefreshesForAWidthReflow() {
        let coordinator = MasonryNavigationCoordinator<Double, Int>()
        update(coordinator, ids: ids, width: 336)
        XCTAssertEqual(coordinator.neighbor(of: 1, toward: .rightward), 2)

        update(coordinator, ids: ids, width: 218)
        XCTAssertNil(coordinator.neighbor(of: 1, toward: .rightward))
    }

    @MainActor
    func testRefreshesWhenOnlyIDsChange() {
        let coordinator = MasonryNavigationCoordinator<Double, Int>()
        update(coordinator, ids: ids, width: 336)
        XCTAssertEqual(coordinator.neighbor(of: 1, toward: .rightward), 2)

        let replacementIDs = [10, 11, 12, 13]
        update(coordinator, ids: replacementIDs, width: 336)
        XCTAssertNil(coordinator.neighbor(of: 1, toward: .rightward))
        XCTAssertEqual(coordinator.neighbor(of: 11, toward: .rightward), 12)
    }

    @MainActor
    func testNavigationUsesTheRenderedSnapshotWithoutMeasuringAgain() {
        let coordinator = MasonryNavigationCoordinator<Double, Int>()
        let snapshot = LayoutSnapshot(
            ids: ids,
            result: layout.layout(items: elements.map { .fixedHeight($0) }, containerWidth: 336),
            containerWidth: 336
        )
        coordinator.update(snapshot: snapshot)

        for _ in 0 ..< 20 {
            XCTAssertEqual(coordinator.neighbor(of: 1, toward: .rightward), 2)
        }
    }

    @MainActor
    private func update(
        _ coordinator: MasonryNavigationCoordinator<Double, Int>,
        ids: [Int],
        width: Double
    ) {
        coordinator.update(snapshot: LayoutSnapshot(
            ids: ids,
            result: layout.layout(items: elements.map { .fixedHeight($0) }, containerWidth: width),
            containerWidth: width
        ))
    }

    private var layout: OiaMasonryLayout {
        OiaMasonryLayout(
            minimumColumnWidth: 100,
            spacing: 18,
            topInset: 0,
            leadingInset: 0,
            bottomInset: 0,
            trailingInset: 0
        )
    }
}
