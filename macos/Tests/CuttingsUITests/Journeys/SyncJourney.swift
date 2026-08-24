// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Files can be added, edited, or deleted by another process while the board is
/// open; the watcher reconciles each change without a restart.
final class SyncJourney: UITestCase {
    func testExternalFileChangesLandLive() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        XCTAssertTrue(list.waitForRowCount(Fixtures.standardCorpus.count), "full board loaded")

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
        XCTAssertTrue(list.row(addedId).waitExists(12), "externally added card appears")
        XCTAssertTrue(list.waitForRowCount(Fixtures.standardCorpus.count + 1), "board count increases")

        var edited = Fixtures.standardCorpus[1]
        edited.title = "Swift Concurrency — Revised Edition"
        edited.body = "# Swift Concurrency — Revised Edition\n\nRevised externally while the app was open.\n"
        try library.write(edited)
        XCTAssertTrue(
            wait(timeout: 10) { list.row(Fixtures.Ids.swift, contains: "Revised") },
            "external title edit updates the card"
        )

        try library.deleteArticle(id: Fixtures.Ids.minimal)
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitDisappears(10), "externally deleted card disappears")
        XCTAssertTrue(list.waitForRowCount(Fixtures.standardCorpus.count), "board count returns")
    }
}
