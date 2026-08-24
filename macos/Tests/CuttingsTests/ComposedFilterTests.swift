// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Pure scope-and-tag filtering rules used by the library board. The async
/// persistence/reconciliation around these rules stays outside this hostless
/// suite.
final class ComposedFilterTests: XCTestCase {
    func testResolveScopeFallsBackToAllOnFavoritesRetap() {
        XCTAssertEqual(
            ComposedFilter.resolveScope(active: .favorites, tapped: .favorites),
            .all
        )
        XCTAssertEqual(ComposedFilter.resolveScope(active: .all, tapped: .all), .all)
        XCTAssertEqual(ComposedFilter.resolveScope(active: .all, tapped: .favorites), .favorites)
    }

    func testToggleClearsOnReselectOtherwiseReplaces() {
        XCTAssertEqual(ComposedFilter.toggle(String?.none, "rust"), "rust")
        XCTAssertNil(ComposedFilter.toggle("rust", "rust"))
        XCTAssertEqual(ComposedFilter.toggle("rust", "swift"), "swift")
    }

    func testChangingScopeClearsTheTag() {
        let current = ComposedFilter.Selection(scope: .all, tag: "swift")
        let next = ComposedFilter.selectingScope(.favorites, from: current)
        XCTAssertEqual(next, ComposedFilter.Selection(scope: .favorites, tag: nil))
    }

    func testFallingBackToAllAlsoClearsTheTag() {
        let current = ComposedFilter.Selection(scope: .favorites, tag: "swift")
        let next = ComposedFilter.selectingScope(.favorites, from: current)
        XCTAssertEqual(next, ComposedFilter.Selection(scope: .all, tag: nil))
    }

    func testTappingAllWhileAlreadyAllKeepsTheTag() {
        let current = ComposedFilter.Selection(scope: .all, tag: "swift")
        XCTAssertEqual(ComposedFilter.selectingScope(.all, from: current), current)
    }

    func testChangingTheTagLeavesTheScopeAlone() {
        let current = ComposedFilter.Selection(scope: .favorites, tag: "swift")
        XCTAssertEqual(
            ComposedFilter.togglingTag("rust", from: current),
            ComposedFilter.Selection(scope: .favorites, tag: "rust")
        )
        XCTAssertEqual(
            ComposedFilter.togglingTag("swift", from: current),
            ComposedFilter.Selection(scope: .favorites, tag: nil)
        )
    }

    func testMatchesIntersectsScopeAndTag() {
        var row = makeReadingRow(favorite: true)
        row.tags = ["rust"]

        XCTAssertTrue(ComposedFilter.matches(row, scope: .all, tag: nil))
        XCTAssertTrue(ComposedFilter.matches(row, scope: .all, tag: "rust"))
        XCTAssertTrue(ComposedFilter.matches(row, scope: .favorites, tag: "rust"))
        XCTAssertFalse(ComposedFilter.matches(row, scope: .all, tag: "swift"))

        row.favorite = false
        XCTAssertFalse(ComposedFilter.matches(row, scope: .favorites, tag: "rust"))
    }

    func testAllMatchesLegacyArchivedRows() {
        let row = makeReadingRow(archived: true)
        XCTAssertTrue(ComposedFilter.matches(row, scope: .all, tag: nil))
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
