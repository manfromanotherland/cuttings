// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

final class BoardSelectionTests: XCTestCase {
    private let ids = ["a", "b", "c", "d", "e"]

    func testPlainSelectionReplacesThePreviousRange() {
        var selection = BoardSelection<String>()
        selection.select("a", extending: false, in: ids)
        selection.select("d", extending: true, in: ids)
        selection.select("b", extending: false, in: ids)

        XCTAssertEqual(selection.focusedID, "b")
        XCTAssertEqual(selection.selectedIDs, ["b"])
    }

    func testExtendedSelectionGrowsAndShrinksFromItsAnchor() {
        var selection = BoardSelection<String>()
        selection.select("b", extending: false, in: ids)
        selection.select("e", extending: true, in: ids)
        XCTAssertEqual(selection.selectedIDs, ["b", "c", "d", "e"])

        selection.select("c", extending: true, in: ids)
        XCTAssertEqual(selection.focusedID, "c")
        XCTAssertEqual(selection.selectedIDs, ["b", "c"])
    }

    func testReconcileDropsUnavailableCardsAndKeepsAVisibleFocus() {
        var selection = BoardSelection<String>()
        selection.select("b", extending: false, in: ids)
        selection.select("d", extending: true, in: ids)

        selection.reconcile(with: ["a", "b", "d", "e"], preserveUnavailableFocus: false)

        XCTAssertEqual(selection.focusedID, "d")
        XCTAssertEqual(selection.selectedIDs, ["b", "d"])
    }

    func testPreservingUnavailableFocusStillPrefersAVisibleSelectedCard() {
        var selection = BoardSelection<String>()
        selection.select("b", extending: false, in: ids)
        selection.select("d", extending: true, in: ids)

        selection.reconcile(with: ["a", "b", "c", "e"], preserveUnavailableFocus: true)

        XCTAssertEqual(selection.focusedID, "b")
        XCTAssertEqual(selection.selectedIDs, ["b", "c"])
    }

    func testRemovingFocusAdvancesThenFallsBack() {
        var selection = BoardSelection<String>()
        selection.select("c", extending: false, in: ids)
        selection.select("d", extending: true, in: ids)

        selection.remove(["c", "d"], from: ids)
        XCTAssertEqual(selection.focusedID, "e")
        XCTAssertEqual(selection.selectedIDs, ["e"])

        selection.remove(["e"], from: ["a", "b", "e"])
        XCTAssertEqual(selection.focusedID, "b")
        XCTAssertEqual(selection.selectedIDs, ["b"])
    }

    func testPartialRemovalKeepsFocusInsideTheRemainingSelection() {
        var selection = BoardSelection<String>()
        selection.select("b", extending: false, in: ids)
        selection.select("d", extending: true, in: ids)

        selection.remove(["d"], from: ids)

        XCTAssertEqual(selection.focusedID, "c")
        XCTAssertEqual(selection.selectedIDs, ["b", "c"])
    }

    func testExtendingFromAnUnavailableFocusStartsANewVisibleRange() {
        var selection = BoardSelection<String>()
        selection.select("a", extending: false, in: ids)
        selection.reconcile(with: ["c", "d", "e"], preserveUnavailableFocus: true)

        selection.select("d", extending: true, in: ["c", "d", "e"])
        XCTAssertEqual(selection.focusedID, "d")
        XCTAssertEqual(selection.selectedIDs, ["d"])

        selection.select("e", extending: true, in: ["c", "d", "e"])
        XCTAssertEqual(selection.selectedIDs, ["d", "e"])
    }
}
