// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `SidebarItem.contains` is the Swift mirror of the core's smart-view clauses
/// (`list.rs`), used to filter rows and to fold optimistic edits into the
/// sidebar counts. These tests pin each of the five views to its membership rule
/// so the mirror can't silently drift from the core.
final class SidebarItemContainsTests: XCTestCase {

    // All: every non-archived reading, regardless of read or favorite.
    func testAllHoldsNonArchivedAndExcludesArchived() {
        XCTAssertTrue(SidebarItem.all.contains(makeReadingRow(archived: false)))
        XCTAssertTrue(SidebarItem.all.contains(makeReadingRow(read: true, archived: false)))
        XCTAssertFalse(SidebarItem.all.contains(makeReadingRow(archived: true)))
        // Archived favorites are still out of All — archive wins here.
        XCTAssertFalse(SidebarItem.all.contains(makeReadingRow(archived: true, favorite: true)))
    }

    // Unread: non-archived and read == false.
    func testUnreadIsNonArchivedAndNotRead() {
        XCTAssertTrue(SidebarItem.unread.contains(makeReadingRow(read: false, archived: false)))
        XCTAssertFalse(SidebarItem.unread.contains(makeReadingRow(read: true, archived: false)))
        XCTAssertFalse(SidebarItem.unread.contains(makeReadingRow(read: false, archived: true)))
    }

    // Read: non-archived and read == true.
    func testReadIsNonArchivedAndRead() {
        XCTAssertTrue(SidebarItem.read.contains(makeReadingRow(read: true, archived: false)))
        XCTAssertFalse(SidebarItem.read.contains(makeReadingRow(read: false, archived: false)))
        // An archived-but-read reading belongs to Archive, not Read.
        XCTAssertFalse(SidebarItem.read.contains(makeReadingRow(read: true, archived: true)))
    }

    // Archive: archived readings only, regardless of read or favorite.
    func testArchiveIsArchivedOnly() {
        XCTAssertTrue(SidebarItem.archive.contains(makeReadingRow(archived: true)))
        XCTAssertTrue(SidebarItem.archive.contains(makeReadingRow(read: true, archived: true)))
        XCTAssertFalse(SidebarItem.archive.contains(makeReadingRow(archived: false)))
    }

    // Favorites: any favorite, including archived favorites.
    func testFavoritesIncludesArchivedFavorites() {
        XCTAssertTrue(SidebarItem.favorites.contains(makeReadingRow(favorite: true)))
        XCTAssertTrue(SidebarItem.favorites.contains(makeReadingRow(archived: true, favorite: true)))
        XCTAssertFalse(SidebarItem.favorites.contains(makeReadingRow(favorite: false)))
    }
}
