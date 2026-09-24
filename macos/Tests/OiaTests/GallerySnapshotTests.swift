// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class GallerySnapshotTests: XCTestCase {
    private struct Row: Identifiable, Equatable {
        let id: Int
        var title: String = "original"
    }

    func testReconciliationPreservesOpeningOrderAndSkipsRemovedNeighbors() {
        var snapshot = GallerySnapshot((0 ..< 6).map { Row(id: $0) })
        snapshot.reconcile([Row(id: 5), Row(id: 0), Row(id: 6)])
        XCTAssertEqual(snapshot.rows.map(\.id), [0, 5])
        XCTAssertEqual(snapshot.neighbor(of: 0, direction: 1)?.id, 5)
        XCTAssertEqual(snapshot.neighbor(of: 3, direction: 1)?.id, 5)
        XCTAssertEqual(snapshot.neighbor(of: 3, direction: -1)?.id, 0)
        XCTAssertNil(snapshot.neighbor(of: 5, direction: 1))
        XCTAssertNil(snapshot.neighbor(of: 0, direction: -1))
    }

    func testOptimisticRowUpdatePreservesNavigationAndCannotReinsertRemovedRows() {
        var snapshot = GallerySnapshot([Row(id: 1), Row(id: 2)])
        snapshot.update(Row(id: 2, title: "edited"))
        XCTAssertEqual(snapshot.neighbor(of: 1, direction: 1)?.title, "edited")
        snapshot.reconcile([Row(id: 1)])
        snapshot.update(Row(id: 2))
        XCTAssertEqual(snapshot.rows.map(\.id), [1])
        XCTAssertNil(snapshot.neighbor(of: 1, direction: 1))
    }
}
