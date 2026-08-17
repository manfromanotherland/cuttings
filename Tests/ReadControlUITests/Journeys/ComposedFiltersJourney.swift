// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The sidebar's three filters — smart view, rating, tag — compose (together with
/// the search box): the list is scoped by their intersection, at most one of each.
/// A selected rating or tag toggles off when clicked again.
///
/// They are also *ordered*: view, then rating, then tag, top to bottom as the
/// sidebar reads. Changing one clears the narrower ones below it — covered by
/// `testChangingTheViewClearsTheRatingAndTag` and
/// `testChangingOrClearingTheRatingClearsTheTag`, with the rules themselves unit
/// tested in `ComposedFilterTests`.
///
/// Corpus (all non-archived), engineered so each intersection is a single known
/// row:
///   A unread·4★·#rust   B read·4★·#rust   C read·4★·#swift
///   D unread·3★·#rust   E unread·(unrated)·#swift
/// So All = 5, Unread = 3 (A,D,E), Read = 2 (B,C), ★4 = 3 (A,B,C),
/// Unread ∩ ★4 = 1 (A), Unread ∩ ★4 ∩ #rust = 1 (A).
final class ComposedFiltersJourney: UITestCase {
    private enum Ids {
        static let alpha = TestULID.make(0)
        static let bravo = TestULID.make(1)
        static let charlie = TestULID.make(2)
        static let delta = TestULID.make(3)
        static let echo = TestULID.make(4)
    }

    private static let corpus: [ArticleFixture] = [
        article(0, "Alpha", tags: ["rust"], rating: 4, read: false),
        article(1, "Bravo", tags: ["rust"], rating: 4, read: true),
        article(2, "Charlie", tags: ["swift"], rating: 4, read: true),
        article(3, "Delta", tags: ["rust"], rating: 3, read: false),
        article(4, "Echo", tags: ["swift"], rating: 0, read: false)
    ]

    // swiftlint:disable function_body_length
    /// One end-to-end cross-filter walk.
    func testViewRatingAndTagCompose() throws {
        // Pin the sort so intersections list deterministically (not asserted here,
        // but keeps the run stable).
        try launchApp(articles: Self.corpus) { options in
            options.pinnedDefaults["sortField"] = "savedAt"
            options.pinnedDefaults["sortAscending"] = "0"
        }

        // Baseline: All 5, Unread 3, and the ★4 badge counts all three (A,B,C).
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 5), "All 5")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 3), "Unread 3 (A,D,E)")
        XCTAssertTrue(sidebar.waitForRatingCount(4, equals: 3), "★4 = A,B,C")

        // 1. Select Unread → the ★4 badge refines to just the unread 4★ (A). The
        //    view no longer replaces the rating; it composes with it.
        sidebar.select(.unread)
        XCTAssertTrue(list.waitForRowCount(3), "Unread lists A,D,E")
        XCTAssertTrue(sidebar.waitForRatingCount(4, equals: 1), "★4 badge 3→1 under Unread (A)")

        // 2. Click ★4 (Unread still active) → the list is the intersection: A only.
        //    This is the behavior that was previously missing (it used to jump to
        //    all six 4★ readings).
        sidebar.selectRating(4)
        XCTAssertTrue(list.waitForRowCount(1), "Unread ∩ ★4 = A")
        XCTAssertTrue(list.row(Ids.alpha).waitExists(), "A present")
        XCTAssertTrue(list.row(Ids.delta).waitDisappears(), "D (3★) filtered out")
        XCTAssertTrue(list.row(Ids.bravo).waitDisappears(), "B (read) filtered out")

        // 3. Add a tag: #rust. Still composes → A (unread ∩ 4★ ∩ #rust).
        sidebar.selectTag("rust")
        XCTAssertTrue(list.waitForRowCount(1), "Unread ∩ ★4 ∩ #rust = A")
        XCTAssertTrue(list.row(Ids.alpha).waitExists(), "A still present")

        // 4. Switch the tag to #swift → no reading is unread ∩ 4★ ∩ #swift, so the
        //    list empties. The other two filters (Unread, ★4) stay put.
        sidebar.selectTag("swift")
        XCTAssertTrue(list.waitForRowCount(0), "Unread ∩ ★4 ∩ #swift = ∅")

        // 5. Toggle #swift off (click it again) → back to Unread ∩ ★4 = A.
        sidebar.selectTag("swift")
        XCTAssertTrue(list.waitForRowCount(1), "clearing the tag restores Unread ∩ ★4 = A")
        XCTAssertTrue(list.row(Ids.alpha).waitExists(), "A present again")

        // 6. Toggle ★4 off → back to plain Unread (A,D,E).
        sidebar.selectRating(4)
        XCTAssertTrue(list.waitForRowCount(3), "clearing the rating restores Unread (A,D,E)")
        XCTAssertTrue(list.row(Ids.delta).waitExists(), "D back in Unread")

        // 7. Click the active Unread view again → it deselects to the All base
        //    (a view always has a value, so it falls back to All, not to nothing),
        //    restoring all 5 readings — including the read ones.
        sidebar.select(.unread)
        XCTAssertTrue(list.waitForRowCount(5), "re-clicking the active view falls back to All (5)")
        XCTAssertTrue(list.row(Ids.bravo).waitExists(), "a read reading (B) is back — we're in All")

        // 8. Clicking All while it's already the base is a no-op — stays at 5.
        sidebar.select(.all)
        XCTAssertTrue(list.waitForRowCount(5), "All stays at 5")
    }

    // swiftlint:enable function_body_length

    // ── Narrowing ─────────────────────────────────────────────────────────

    /// Switching the smart view clears both the rating and the tag beneath it.
    /// The oracle is C: it's `#swift`, so it can only appear once the `#rust` tag
    /// is gone — a list of 2 means the cascade ran, a list of 1 means it didn't.
    func testChangingTheViewClearsTheRatingAndTag() throws {
        try launchApp(articles: Self.corpus)

        sidebar.select(.unread)
        sidebar.selectRating(4)
        sidebar.selectTag("rust")
        XCTAssertTrue(list.waitForRowCount(1), "Unread ∩ ★4 ∩ #rust = A")

        sidebar.select(.read)
        XCTAssertTrue(list.waitForRowCount(2), "Read alone = B,C — ★4 and #rust were cleared")
        XCTAssertTrue(list.row(Ids.charlie).waitExists(), "C (#swift) lists only if the tag went")
    }

    /// Changing the rating clears the tag, and so does clearing the rating.
    /// D is the oracle both times: it's `#rust`, so it can only list once `#swift`
    /// has gone.
    func testChangingOrClearingTheRatingClearsTheTag() throws {
        try launchApp(articles: Self.corpus)

        sidebar.selectRating(4)
        sidebar.selectTag("swift")
        XCTAssertTrue(list.waitForRowCount(1), "★4 ∩ #swift = C")

        // ★4 → ★3 is a change at the rating level, so #swift goes with it.
        sidebar.selectRating(3)
        XCTAssertTrue(list.waitForRowCount(1), "★3 alone = D — #swift was cleared")
        XCTAssertTrue(list.row(Ids.delta).waitExists(), "D (#rust) lists only if the tag went")

        // Broadening cascades too: toggling ★3 off clears the tag under it.
        sidebar.selectTag("rust")
        XCTAssertTrue(list.waitForRowCount(1), "★3 ∩ #rust = D")
        sidebar.selectRating(3)
        XCTAssertTrue(list.waitForRowCount(5), "clearing ★3 cleared #rust too — All = 5")
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static func article(
        _ index: Int, _ title: String,
        tags: [String], rating: UInt8, read: Bool
    ) -> ArticleFixture {
        ArticleFixture(
            id: TestULID.make(index),
            url: "https://example.com/\(index)",
            title: title,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index) * 86400),
            tags: tags,
            readAt: read ? Date(timeIntervalSince1970: 1_710_000_000) : nil,
            rating: rating,
            site: "example.com",
            body: "# \(title)\n\nBody of \(title).\n"
        )
    }
}
