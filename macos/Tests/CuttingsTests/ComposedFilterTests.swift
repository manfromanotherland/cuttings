// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Pure filtering and one-motion selection rules used by the library board.
final class ComposedFilterTests: XCTestCase {
    func testMatchesUsesTheSelectedScope() {
        let favorite = makeReadingRow(favorite: true)
        XCTAssertTrue(ComposedFilter.matches(favorite, scope: .all))
        XCTAssertTrue(ComposedFilter.matches(favorite, scope: .favorites))

        let ordinary = makeReadingRow()
        XCTAssertTrue(ComposedFilter.matches(ordinary, scope: .all))
        XCTAssertFalse(ComposedFilter.matches(ordinary, scope: .favorites))
    }

    func testAllMatchesLegacyArchivedRows() {
        let row = makeReadingRow(archived: true)
        XCTAssertTrue(ComposedFilter.matches(row, scope: .all))
    }

    func testSelectionAfterRemovingPrefersNextThenPreviousThenNil() {
        let rows = [rowWithId("a"), rowWithId("b"), rowWithId("c")]
        XCTAssertEqual(ComposedFilter.selectionAfterRemoving(at: 0, from: rows), "b")
        XCTAssertEqual(ComposedFilter.selectionAfterRemoving(at: 2, from: rows), "b")
        XCTAssertNil(ComposedFilter.selectionAfterRemoving(at: 0, from: [rowWithId("only")]))
    }

    private func rowWithId(_ id: String) -> ReadingRow {
        var row = makeReadingRow()
        row.id = id
        return row
    }
}
