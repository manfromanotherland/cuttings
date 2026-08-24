// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Faceted, *pinned* sidebar counts. Every section's badges track the active
/// search and the selected facet, but the tiles themselves stay put — a tag or
/// rating with no results shows no number rather than disappearing, exactly like
/// the smart-view rows. Selecting a facet refines the *other* sections, never
/// itself.
///
/// A purpose-built corpus makes the numbers exact. "starship" appears in five
/// readings; two controls omit it:
///   M1 active·unread·5★·#scifi   M2 active·read·5★·#scifi
///   M3 active·unread·3★·#space   M4 archived·5★·#scifi
///   M5 active·unread·favorite·#space (unrated)
///   N1 active·unread·5★·#scifi — no "starship" (shares scifi/5★; search drops it)
///   K1 active·unread·2★·#cooking — no "starship" (its tag/rating never match)
///
/// Non-archived is the base for the Tags/Ratings sections (view All), so M4 is
/// excluded there; it still shows under the Archive smart-view badge.
final class SearchFacetCountsJourney: UITestCase {
    private static let corpus: [ArticleFixture] = [
        article(0, "Starbound", tags: ["scifi"], rating: 5,
                body: "A lone starship drifts past Neptune."),
        article(1, "Return Voyage", tags: ["scifi"], rating: 5, read: true,
                body: "The starship came home at last."),
        article(2, "Orbital Notes", tags: ["space"], rating: 3,
                body: "Docking a starship needs patience."),
        article(3, "Old Logs", tags: ["scifi"], rating: 5, archived: true,
                body: "An abandoned starship, filed away."),
        article(4, "Bright Sail", tags: ["space"], favorite: true,
                body: "A solar starship unfurls its sail."),
        // Control 1 (#scifi, 5★, no "starship"): the search drops it, so it never
        // inflates the faceted scifi / 5★ counts.
        article(5, "Nebula Recipes", tags: ["scifi"], rating: 5,
                body: "Tonight I cooked pasta."),
        // Control 2 (#cooking, 2★, no "starship"): its tag and rating never match
        // the search, so they prove pinning — the tile/row stays at 0.
        article(6, "Pasta Night", tags: ["cooking"], rating: 2,
                body: "More pasta, more bread.")
    ]

    // swiftlint:disable function_body_length
    /// One end-to-end faceting walk.
    func testSearchAndFacetScopeSidebarCounts() throws {
        try launchApp(articles: Self.corpus)

        // 0. Baseline (no search): the badges count the whole library. The 5★ and
        //    #scifi buckets include the control N1 here — the search will drop it.
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 6), "All 6 (M4 archived)")
        XCTAssertTrue(sidebar.waitForRatingCount(5, equals: 3), "★5 = M1, M2, N1")
        XCTAssertTrue(sidebar.waitForTagCount("scifi", equals: 3), "#scifi = M1, M2, N1")
        XCTAssertTrue(sidebar.waitForTagCount("cooking", equals: 1), "#cooking = K1")

        // 1. Search "starship" → the four matching *active* readings; the controls
        //    (no "starship") and the archived M4 are out of the All view.
        keyboard.focusSearch()
        list.search("starship")
        XCTAssertTrue(list.waitForRowCount(4), "All-view matches: M1, M2, M3, M5")

        // 2. Every badge now counts only "starship" matches, but the tiles stay put.
        //    Library spans all views; Ratings/Tags stay non-archived.
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 4), "All: M1, M2, M3, M5")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 3), "Unread: M1, M3, M5")
        XCTAssertTrue(sidebar.waitForCount(.read, equals: 1), "Read: M2")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 1), "Archive: M4")
        XCTAssertTrue(sidebar.waitForCount(.favorites, equals: 1), "Favorites: M5")
        XCTAssertTrue(sidebar.waitForRatingCount(5, equals: 2), "★5 → M1, M2 (N1 dropped)")
        XCTAssertTrue(sidebar.waitForRatingCount(3, equals: 1), "★3 → M3")
        XCTAssertTrue(sidebar.waitForTagCount("scifi", equals: 2), "#scifi → M1, M2 (N1 dropped)")
        XCTAssertTrue(sidebar.waitForTagCount("space", equals: 2), "#space → M3, M5")
        // Pinned: the #cooking tag and the ★2 bucket have no "starship" match, yet
        // their tile/row stay visible with the number hidden (count 0).
        XCTAssertTrue(sidebar.tagTile("cooking").waitExists(), "#cooking tile stays pinned")
        XCTAssertEqual(sidebar.tagCount("cooking"), 0, "#cooking badge shows 0")
        XCTAssertTrue(sidebar.ratingRow(2).waitExists(), "★2 row stays pinned")
        XCTAssertEqual(sidebar.ratingCount(2), 0, "★2 badge shows 0")

        // 3. Click ★5 (still searching). The Ratings section — the one selected —
        //    is unchanged; the Library and Tags sections refine to the 5★ subset.
        sidebar.selectRating(5)
        // List = All ∩ ★5 ∩ "starship" = M1, M2 (proves the search persisted: with
        // no search it would also include the control N1, giving three rows).
        XCTAssertTrue(list.waitForRowCount(2), "★5 + search narrows to M1, M2")

        // Library recounts against the 5★ subset. Archive still shows M4 (a facet
        // is scoped by the search, not by the active smart view).
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 2), "All → M1, M2")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 1), "Unread → M1")
        XCTAssertTrue(sidebar.waitForCount(.read, equals: 1), "Read → M2")
        XCTAssertTrue(sidebar.waitForCount(.archive, equals: 1), "Archive → M4 (5★)")
        XCTAssertTrue(sidebar.waitForCount(.favorites, equals: 0), "Favorites → none (M5 is unrated)")

        // Ratings (the selected section) keep the search-scoped counts — its own
        // selection never filters itself, so you can still switch buckets.
        XCTAssertTrue(sidebar.waitForRatingCount(5, equals: 2), "★5 unchanged")
        XCTAssertTrue(sidebar.waitForRatingCount(3, equals: 1), "★3 unchanged")

        // Tags refine to the 5★ subset: #scifi keeps its count while #space and
        // #cooking drop to 0 — all three tiles stay pinned.
        XCTAssertTrue(sidebar.waitForTagCount("scifi", equals: 2), "#scifi → M1, M2")
        XCTAssertTrue(sidebar.tagTile("space").waitExists(), "#space tile stays pinned at 5★")
        XCTAssertEqual(sidebar.tagCount("space"), 0, "#space badge shows 0")
        XCTAssertTrue(sidebar.tagTile("cooking").waitExists(), "#cooking tile stays pinned at 5★")
        XCTAssertEqual(sidebar.tagCount("cooking"), 0, "#cooking badge shows 0")
    }

    // swiftlint:enable function_body_length

    // ── Helpers ───────────────────────────────────────────────────────────

    /// A fixture whose id sequence == `index`, so ids (and the default saved-at
    /// order) sort deterministically. This journey asserts counts, not order.
    private static func article(
        _ index: Int, _ title: String,
        tags: [String], rating: UInt8 = 0,
        read: Bool = false, archived: Bool = false, favorite: Bool = false,
        body: String
    ) -> ArticleFixture {
        ArticleFixture(
            id: TestULID.make(index),
            url: "https://example.com/\(index)",
            title: title,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index) * 86400),
            archived: archived,
            favorite: favorite,
            tags: tags,
            readAt: read ? Date(timeIntervalSince1970: 1_710_000_000) : nil,
            rating: rating,
            site: "example.com",
            body: "# \(title)\n\n\(body)\n"
        )
    }
}
