// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Weekend cleanup: declutter by archiving what's done and purging what's
/// dead. Batch-archive the read articles from All (each leaving in one motion
/// with the selection advancing), review the Archive pile, move one back to the
/// library, then permanently delete a couple — asserting the confirmation
/// dialog, the row removal, and the `.md` file leaving disk, plus a cancel path
/// that leaves its article untouched.
///
/// The fixed newest-saved-first All order is deterministic
/// ([7,6,5,4,3,2,1,0]) and the selection-advance target is known. The three read
/// active articles are `ratedThree` (idx6), `favoriteRead` (idx5) and `rust`
/// (idx0); archiving idx6 advances the selection to idx5, which is archived next.
final class WeekendCleanupJourney: UITestCase {
    // A single declutter walk; asserting every beat keeps it long.
    // swiftlint:disable:next function_body_length
    func testArchiveReviewUnarchiveAndDelete() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        XCTAssertTrue(sidebar.waitForCount(.all, equals: Fixtures.Oracle.ViewCounts.all), "All starts at 8")

        // 1. In All, archive the read articles one after another. Each row leaves
        //    in one motion, the selection advances, Archive climbs and All drops.
        list.open(Fixtures.Ids.ratedThree)
        XCTAssertEqual(reader.titleText, "A Programming Note")

        keyboard.archive()
        XCTAssertTrue(list.row(Fixtures.Ids.ratedThree).waitDisappears(), "idx6 leaves All")
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 7), "All 8→7")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 3), "Archive 2→3")
        XCTAssertEqual(reader.titleText, "A Favorite Reading", "selection advanced to idx5")

        // idx5 is now selected — archive it too.
        keyboard.archive()
        XCTAssertTrue(list.row(Fixtures.Ids.favoriteRead).waitDisappears(), "idx5 leaves All")
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 6), "All 7→6")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 4), "Archive 3→4")

        list.open(Fixtures.Ids.rust)
        keyboard.archive()
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitDisappears(), "idx0 leaves All")
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 5), "All 6→5")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 5), "Archive 4→5")

        // 2. Switch to Archive to review → the three just-archived articles are
        //    there (alongside the two originally archived).
        sidebar.select(.archive)
        XCTAssertTrue(list.waitForRowCount(5), "Archive holds five")
        XCTAssertTrue(list.row(Fixtures.Ids.ratedThree).waitExists(), "idx6 in Archive")
        XCTAssertTrue(list.row(Fixtures.Ids.favoriteRead).waitExists(), "idx5 in Archive")
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitExists(), "idx0 in Archive")

        // 3. One is worth keeping handy → Move to Library (unarchive) idx6. It
        //    leaves Archive and returns to All; counts move back.
        list.open(Fixtures.Ids.ratedThree)
        reader.unarchive()
        XCTAssertTrue(list.row(Fixtures.Ids.ratedThree).waitDisappears(), "idx6 leaves Archive")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 4), "Archive 5→4")
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 6), "All 5→6")
        sidebar.select(.all)
        XCTAssertTrue(list.row(Fixtures.Ids.ratedThree).waitExists(), "idx6 back in All")

        // 4. Permanently delete a couple of dead ones from Archive (toolbar Delete
        //    → confirmation dialog → Delete): each row goes and its `.md` file is
        //    removed from disk. Then cancel the dialog on one — it stays untouched.
        sidebar.select(.archive)
        XCTAssertTrue(list.waitForRowCount(4), "Archive holds four before deletes")

        list.open(Fixtures.Ids.archived)
        reader.delete()
        list.confirmDelete()
        XCTAssertTrue(list.row(Fixtures.Ids.archived).waitDisappears(), "deleted idx8 row gone")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 3), "Archive 4→3")
        XCTAssertTrue(wait { library.articleExists(id: Fixtures.Ids.archived) == false }, "idx8 .md removed from disk")

        list.open(Fixtures.Ids.rust)
        reader.delete()
        list.confirmDelete()
        XCTAssertTrue(list.row(Fixtures.Ids.rust).waitDisappears(), "deleted idx0 row gone")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 2), "Archive 3→2")
        XCTAssertTrue(wait { library.articleExists(id: Fixtures.Ids.rust) == false }, "idx0 .md removed from disk")

        // Cancel path: open the last dead one, invoke Delete, then Cancel → the row
        // and file both survive.
        list.open(Fixtures.Ids.archivedFavorite)
        reader.delete()
        list.cancelDelete()
        XCTAssertTrue(list.row(Fixtures.Ids.archivedFavorite).waitExists(), "cancelled row stays")
        XCTAssertEqual(sidebar.count(of: .archive), 2, "Archive still 2 after cancel")
        XCTAssertTrue(library.articleExists(id: Fixtures.Ids.archivedFavorite), "cancelled article's .md untouched")
    }
}
