// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Living with sync: files change underneath the app. With the app open on
/// a seeded library, the test plays the "other device" and writes directly to the
/// library folder; each change must land live through the FSEvents watcher +
/// reconcile — no restart. This validates the project's crown-jewel principles:
/// files are the source of truth, and the app is never the only writer.
///
/// Watcher waits are generous (10–12 s): FSEvents latency (~0.5 s) plus the
/// incremental reconcile, with a little headroom for the watcher to warm up right
/// after launch.
final class SyncJourney: UITestCase {
    // swiftlint:disable function_body_length
    /// A single sync walk exercising add / edit / read / delete.
    func testExternalFileChangesLandLive() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        XCTAssertTrue(sidebar.waitForCount(.all, equals: Fixtures.Oracle.ViewCounts.all), "All starts at 8")

        // 1. An external process ADDS a new article file. Within a moment the row
        //    appears and the All/Unread counts tick up — no restart.
        let addedId = Fixtures.id(50)
        let added = ArticleFixture(
            id: addedId,
            url: "https://example.com/synced",
            title: "Synced From Another Device",
            savedAt: Date(),
            site: "example.com",
            excerpt: "Arrived through the watcher.",
            wordCount: 400,
            body: "# Synced From Another Device\n\nWritten externally while the app was open.\n"
        )
        try library.write(added)
        XCTAssertTrue(list.row(addedId).waitExists(12), "externally-added row appears live")
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 9, timeout: 10), "All 8→9")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 6, timeout: 10), "Unread 5→6")

        // 2. An external process EDITS an existing article's title (rewriting the
        //    file, which recomputes source_hash and bumps mtime). The row's title
        //    updates in place.
        var edited = Fixtures.standardCorpus[1] // idx1 — "Swift Concurrency Explained"
        edited.title = "Swift Concurrency — Revised Edition"
        // Change the body too: the core's incremental diff keys solely on
        // source_hash (sha256 of the body), so a title-only rewrite carries the
        // same hash and is skipped as a no-op. Real external content edits
        // recompute the body, so this rewrites it to force a fresh source_hash.
        edited.body = "# Swift Concurrency — Revised Edition\n\nRevised externally while the app was open.\n"
        try library.write(edited)
        XCTAssertTrue(
            wait(timeout: 10) { list.row(Fixtures.Ids.swift, contains: "Revised") },
            "the edited title updates the row in place"
        )

        // 3. An external process MARKS an article read by adding read_at to its
        //    file. Watched from Unread, the article leaves the view and the count
        //    drops.
        sidebar.select(.unread)
        XCTAssertTrue(list.row(Fixtures.Ids.unicode).waitExists(), "unread article present in Unread")
        var markedRead = Fixtures.standardCorpus[3] // idx3 — unicode, unread
        markedRead.readAt = Date()
        // Bump the body so source_hash changes; a metadata-only rewrite shares the
        // old hash and the diff skips it (same reason as step 2).
        markedRead.body = "# Café Über 日本語 🎉\n\nMarked read externally.\n"
        try library.write(markedRead)
        XCTAssertTrue(list.row(Fixtures.Ids.unicode).waitDisappears(10), "read article leaves Unread")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 5, timeout: 10), "Unread 6→5")

        // 4. An external process DELETES a file. Its row disappears from the list
        //    and the counts drop.
        try library.deleteArticle(id: Fixtures.Ids.minimal) // idx4 — unread
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitDisappears(10), "deleted file's row disappears")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 4, timeout: 10), "Unread 5→4")
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 8, timeout: 10), "All 9→8")
    }
    // swiftlint:enable function_body_length
}
