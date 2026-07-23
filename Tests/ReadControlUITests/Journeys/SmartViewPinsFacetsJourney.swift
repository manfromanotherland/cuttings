// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Selecting a smart view must not drop tag/rating tiles: those sections are a
/// fixed set, like the Library rows, so switching view only rescopes the badges
/// — a tag or rating with no result in the new view stays pinned at 0 rather than
/// disappearing. This holds for two views with *different* presence semantics,
/// checked in one launch:
///   • Favorites — a cross-cutting flag, no search active.
///   • Unread — part of the All/Unread/Read shared pool, with a search active.
///
/// Two readings do double duty. A survives both views (it's favorite *and*
/// unread); B is zeroed by both (it's non-favorite *and* read). Both bodies carry
/// "coding" so the Unread phase's search keeps them:
///   A favorite·unread·5★·#alpha   B not-favorite·read·3★·#beta
final class SmartViewPinsFacetsJourney: UITestCase {
    private static let corpus: [ArticleFixture] = [
        article(0, tags: ["alpha"], rating: 5, read: false, favorite: true),
        article(1, tags: ["beta"], rating: 3, read: true, favorite: false)
    ]

    // One launch, two view-pinning phases: Favorites (no search), then Unread
    // (with search).
    func testSmartViewsKeepFacetTilesPinned() throws {
        try launchApp(articles: Self.corpus)

        // Baseline (All view, no search): both tags and both ratings present.
        XCTAssertTrue(sidebar.waitForTagCount("alpha", equals: 1), "#alpha = A")
        XCTAssertTrue(sidebar.waitForTagCount("beta", equals: 1), "#beta = B")
        XCTAssertTrue(sidebar.waitForRatingCount(5, equals: 1), "★5 = A")
        XCTAssertTrue(sidebar.waitForRatingCount(3, equals: 1), "★3 = B")

        // ── Phase 1: Favorites view pins facets (no search) ──────────────────
        // Only A is a favorite, so B's tag/rating drop to 0 — but their tile/row
        // stay pinned, because favorite is a cross-cutting flag, not a pool split.
        sidebar.select(.favorites)
        XCTAssertTrue(list.waitForRowCount(1), "Favorites = A only")

        XCTAssertTrue(sidebar.waitForTagCount("alpha", equals: 1), "#alpha → 1 (A is a favorite)")
        XCTAssertTrue(sidebar.tagTile("beta").waitExists(), "#beta tile stays pinned in Favorites")
        XCTAssertEqual(sidebar.tagCount("beta"), 0, "#beta badge shows 0 (B isn't a favorite)")

        XCTAssertTrue(sidebar.waitForRatingCount(5, equals: 1), "★5 → 1 (A is a favorite)")
        XCTAssertTrue(sidebar.ratingRow(3).waitExists(), "★3 row stays pinned in Favorites")
        XCTAssertEqual(sidebar.ratingCount(3), 0, "★3 badge shows 0 (B isn't a favorite)")

        // Back to the All base so the next phase starts unfiltered.
        sidebar.select(.all)
        XCTAssertTrue(list.waitForRowCount(2), "All lists A and B again")

        // ── Phase 2: Unread view pins facets (search active) ─────────────────
        // Search "coding" (both match), then click Unread. Only A is unread, so
        // #beta and ★3 (B, which is read) drop to 0 — the tile/row stay pinned,
        // because All/Unread/Read share one presence pool.
        keyboard.focusSearch()
        // Paste, don't type: this host drops a leading "c", so a typed "coding"
        // arrives as "oding" and matches nothing. `pasteSearch` sidesteps that.
        list.pasteSearch("coding")
        XCTAssertTrue(list.waitForRowCount(2), "both readings match \"coding\"")
        XCTAssertTrue(sidebar.waitForTagCount("alpha", equals: 1), "#alpha still 1")
        XCTAssertTrue(sidebar.waitForTagCount("beta", equals: 1), "#beta still 1")

        sidebar.select(.unread)
        XCTAssertTrue(list.waitForRowCount(1), "Unread ∩ coding = A only")

        XCTAssertTrue(sidebar.waitForTagCount("alpha", equals: 1), "#alpha → 1 (A is unread)")
        XCTAssertTrue(sidebar.tagTile("beta").waitExists(), "#beta tile stays pinned in Unread")
        XCTAssertEqual(sidebar.tagCount("beta"), 0, "#beta badge shows 0 (B is read)")

        XCTAssertTrue(sidebar.waitForRatingCount(5, equals: 1), "★5 → 1 (A is unread)")
        XCTAssertTrue(sidebar.ratingRow(3).waitExists(), "★3 row stays pinned in Unread")
        XCTAssertEqual(sidebar.ratingCount(3), 0, "★3 badge shows 0 (B is read)")
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// A fixture whose id sequence == `index`, so ids and the default saved-at
    /// order stay deterministic. Every body carries "coding" so both readings
    /// match the Unread phase's search. This journey asserts counts, not titles.
    private static func article(
        _ index: Int, tags: [String],
        rating: UInt8, read: Bool, favorite: Bool
    ) -> ArticleFixture {
        ArticleFixture(
            id: TestULID.make(index),
            url: "https://example.com/\(index)",
            title: "Reading \(index)",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index) * 86_400),
            favorite: favorite,
            tags: tags,
            readAt: read ? Date(timeIntervalSince1970: 1_710_000_000) : nil,
            rating: rating,
            site: "example.com",
            body: "# Reading \(index)\n\nSome coding notes.\n"
        )
    }
}
