// SPDX-License-Identifier: GPL-3.0-or-later

import LazyLayoutKit
import Observation
import XCTest

final class BoardVisibilityCoordinatorTests: XCTestCase {
    @MainActor
    func testOnlyCardsCrossingTheViewportPublishVisibilityChanges() {
        let coordinator = BoardVisibilityCoordinator<Int>()
        coordinator.update(snapshot: snapshot(ids: [0, 1, 2, 3]))
        let first = coordinator.tracker(for: 0)
        let second = coordinator.tracker(for: 1)
        coordinator.update(viewport: viewport(y: 0))
        XCTAssertTrue(first.isVisible)
        XCTAssertFalse(second.isVisible)

        let changes = ChangeCounter()
        withObservationTracking { _ = first.isVisible } onChange: { changes.increment() }
        coordinator.update(viewport: viewport(y: 1))
        coordinator.update(viewport: viewport(y: 5))
        XCTAssertEqual(changes.value, 0, "raw offsets must not invalidate an unchanged card")
        XCTAssertTrue(second.isVisible)

        coordinator.update(viewport: viewport(y: 100))
        XCTAssertFalse(first.isVisible)
        XCTAssertTrue(second.isVisible)
        XCTAssertEqual(changes.value, 1)
    }

    @MainActor
    func testReplacingSnapshotClearsRemovedCardAndInitializesNewTrackers() {
        let coordinator = BoardVisibilityCoordinator<Int>()
        coordinator.update(snapshot: snapshot(ids: [0, 1, 2, 3]))
        coordinator.update(viewport: viewport(y: 0))
        let old = coordinator.tracker(for: 0)
        XCTAssertTrue(old.isVisible)

        coordinator.update(snapshot: snapshot(ids: [10, 11, 12, 13]))
        XCTAssertFalse(old.isVisible)
        XCTAssertTrue(coordinator.tracker(for: 10).isVisible)
        XCTAssertFalse(coordinator.tracker(for: 13).isNearViewport)
    }

    @MainActor
    func testDiscardedCellsAreNotRetainedByTheCoordinator() {
        let coordinator = BoardVisibilityCoordinator<Int>()
        weak var released: BoardCardVisibility?
        autoreleasepool {
            let tracker = coordinator.tracker(for: 0)
            released = tracker
        }
        XCTAssertNil(released)
    }

    private func snapshot(ids: [Int]) -> LayoutSnapshot<Int> {
        LayoutSnapshot(
            ids: ids,
            result: LazyLayoutResult(
                frames: (0 ..< ids.count).map {
                    LayoutRect(x: 0, y: Double($0 * 100), width: 100, height: 100)
                },
                contentHeight: Double(ids.count * 100)
            ),
            containerWidth: 100
        )
    }

    private func viewport(y offset: Double) -> LayoutRect {
        LayoutRect(x: 0, y: offset, width: 100, height: 100)
    }
}

private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
