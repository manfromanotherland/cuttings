// SPDX-License-Identifier: GPL-3.0-or-later

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
    func testRefreshesWhenOnlyConfigurationIDChanges() {
        let coordinator = MasonryNavigationCoordinator<Double, Int>()
        var estimationCount = 0

        func update(configurationID: String) {
            coordinator.updateIfNeeded(
                elements: elements,
                ids: ids,
                configuration: MasonryNavigationConfiguration(
                    layout: layout,
                    containerWidth: 336,
                    configurationID: configurationID
                ),
                estimatedHeight: { _, _ in
                    estimationCount += 1
                    return 100
                }
            )
        }

        update(configurationID: CardSize.small.rawValue)
        XCTAssertEqual(estimationCount, elements.count)

        update(configurationID: CardSize.small.rawValue)
        XCTAssertEqual(estimationCount, elements.count)

        update(configurationID: CardSize.large.rawValue)
        XCTAssertEqual(estimationCount, elements.count * 2)
    }

    @MainActor
    private func update(
        _ coordinator: MasonryNavigationCoordinator<Double, Int>,
        ids: [Int],
        width: Double
    ) {
        coordinator.updateIfNeeded(
            elements: elements,
            ids: ids,
            configuration: MasonryNavigationConfiguration(
                layout: layout,
                containerWidth: width,
                configurationID: 0
            ),
            estimatedHeight: { _, _ in 100 }
        )
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
