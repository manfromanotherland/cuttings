// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The shared, fixed set of fake readings every journey asserts against, plus
/// the **oracle** constants (known counts and orderings) derived from it. The
/// oracles are hand-computed against the real core's rules, verified in
/// `list.rs` / `tags.rs` / `rating.rs`:
///
/// - views: All =`archived=0`, Unread =`archived=0 & read_at IS NULL`,
///   Read =`archived=0 & read_at IS NOT NULL`, Archive =`archived=1`,
///   Favorites =`favorite=1` (crosses archive);
/// - tag counts: non-archived only, count desc then name asc;
/// - rating counts: non-archived, ratings 1–5, rating desc;
/// - sort: `field DIR, id DESC`, with `read_at`/`word_count` NULLs forced last
///   in both directions; the app default is `saved_at` descending.
///
/// Every article's id is `TestULID.make(index)`, so ids sort in index order —
/// which makes the `id DESC` tiebreak (and the whole default ordering) predictable.
enum Fixtures {
    // ── Ids ───────────────────────────────────────────────────────────────
    // Stable ids for the articles journeys refer to by role.
    enum Ids {
        static let rust = id(0)            // "ownership" — active, read
        static let swift = id(1)           // "concurrency" — active, unread
        static let kitchenSink = id(2)     // long, every markdown block + asset image
        static let unicode = id(3)         // emoji/diacritic title
        static let minimal = id(4)         // only required frontmatter fields
        static let favoriteRead = id(5)    // active, read, favorite
        static let ratedThree = id(6)      // active, read
        static let swiftTips = id(7)       // active, unread, favorite
        static let archived = id(8)        // archived, read ("sabbatical")
        static let archivedFavorite = id(9)// archived AND favorite (crosses archive)
        static let oversize = id(200)      // ~11 MB body; not in standardCorpus
    }

    /// A ULID for a corpus index (ids sort in index order).
    static func id(_ index: Int) -> String { TestULID.make(index) }

    // ── Standard corpus ─────────────────────────────────────────────────────

    /// ~10 articles spanning the state space. Index order == `saved_at` order.
    static let standardCorpus: [ArticleFixture] = [
        // 0 — Rust article; the only place the term "ownership" appears.
        ArticleFixture(
            id: id(0), url: "https://blog.rust-lang.org/ownership",
            title: "Understanding Rust Ownership", savedAt: saved(0),
            tags: ["rust", "programming"], readAt: readAt("2026-02-01T09:00:00Z"),
            rating: 5, author: "Alice Rustacean", site: "blog.rust-lang.org",
            excerpt: "How the borrow checker keeps memory safe.", wordCount: 1200, lang: "en",
            body: "# Understanding Rust Ownership\n\n"
                + "Rust's ownership model guarantees memory safety without a garbage collector.\n"
        ),
        // 1 — Swift article; the only place the term "concurrency" appears.
        ArticleFixture(
            id: id(1), url: "https://swift.org/concurrency",
            title: "Swift Concurrency Explained", savedAt: saved(1),
            tags: ["swift", "programming"],
            author: "Bob Appleseed", site: "swift.org",
            excerpt: "Structured concurrency with async and await.", wordCount: 2500, lang: "en",
            body: "# Swift Concurrency Explained\n\n"
                + "Swift concurrency uses async and await to structure work.\n"
        ),
        // 2 — Kitchen-sink markdown, long; starts unrated/unfavorited for the deep-read journey.
        ArticleFixture(
            id: id(2), url: "https://example.com/markdown-sample",
            title: "The Complete Markdown Sample", savedAt: saved(2),
            tags: ["markdown"], author: "Casey Docs", site: "example.com",
            excerpt: "A demonstration of every supported block.", wordCount: 5000, lang: "en",
            body: kitchenSinkBody
        ),
        // 3 — Unicode/emoji title (diacritic-insensitive search target: "cafe" → "café").
        ArticleFixture(
            id: id(3), url: "https://example.com/unicode",
            title: "Café Über 日本語 🎉", savedAt: saved(3),
            tags: ["unicode"], rating: 1, site: "example.com",
            excerpt: "Emoji and accents render correctly.", wordCount: 300, lang: "en",
            body: "# Café Über 日本語 🎉\n\nEmoji test: 🎉🚀. Everything renders.\n"
        ),
        // 4 — Minimal: only the required frontmatter fields, empty tags, no body extras.
        ArticleFixture(
            id: id(4), url: "https://example.com/minimal",
            title: "Minimal", savedAt: saved(4),
            body: "# Minimal\n\nJust the basics.\n"
        ),
        // 5 — Active, read, favorite, rating 4.
        ArticleFixture(
            id: id(5), url: "https://example.com/favorite",
            title: "A Favorite Reading", savedAt: saved(5),
            favorite: true, tags: ["rust"], readAt: readAt("2026-02-10T09:00:00Z"),
            rating: 4, author: "Dana Reader", site: "example.com",
            excerpt: "One to keep.", wordCount: 1800, lang: "en"
        ),
        // 6 — Active, read, rating 3.
        ArticleFixture(
            id: id(6), url: "https://example.com/note",
            title: "A Programming Note", savedAt: saved(6),
            tags: ["programming"], readAt: readAt("2026-02-15T09:00:00Z"),
            rating: 3, author: "Erin Coder", site: "example.com",
            excerpt: "A short note.", wordCount: 600, lang: "en"
        ),
        // 7 — Active, unread, favorite, rating 2.
        ArticleFixture(
            id: id(7), url: "https://example.com/tips",
            title: "Swift Tips", savedAt: saved(7),
            favorite: true, tags: ["swift"], rating: 2,
            author: "Frankie Dev", site: "example.com",
            excerpt: "Handy tips.", wordCount: 3200, lang: "en"
        ),
        // 8 — Archived, read; the only place the term "sabbatical" appears.
        ArticleFixture(
            id: id(8), url: "https://example.com/archived",
            title: "Archived Notes", savedAt: saved(8),
            archived: true, tags: ["archived-tag"], readAt: readAt("2026-02-20T09:00:00Z"),
            author: "Gale Filer", site: "example.com",
            excerpt: "Set aside for later.", wordCount: 900, lang: "en",
            body: "# Archived Notes\n\nWritten during a long sabbatical away from the office.\n"
        ),
        // 9 — Archived AND favorite, rating 5: proves favorites cross the archive
        //     boundary, and that archived rows are excluded from tag/rating counts.
        ArticleFixture(
            id: id(9), url: "https://example.com/archived-favorite",
            title: "Archived Favorite", savedAt: saved(9),
            archived: true, favorite: true, tags: ["rust"], readAt: readAt("2026-02-25T09:00:00Z"),
            rating: 5, author: "Harper Keep", site: "example.com",
            excerpt: "Kept even though archived.", wordCount: 1500, lang: "en"
        ),
    ]

    // ── Oracles ─────────────────────────────────────────────────────────────

    enum Oracle {
        /// Sidebar smart-view badge counts.
        enum ViewCounts {
            static let all = 8
            static let unread = 5
            static let read = 3
            static let archive = 2
            static let favorites = 3
        }

        /// Sidebar Tags section: non-archived only, count desc then name asc.
        static let tagCounts: [(tag: String, count: Int)] = [
            ("programming", 3), ("rust", 2), ("swift", 2), ("markdown", 1), ("unicode", 1),
        ]

        /// Sidebar Ratings section: non-archived, ratings 1–5, rating desc. Each
        /// bucket has one article (5→idx0, 4→idx5, 3→idx6, 2→idx7, 1→idx3); idx9
        /// is rating 5 but archived, so it's excluded.
        static let ratingCounts: [(rating: UInt8, count: Int)] = [
            (5, 1), (4, 1), (3, 1), (2, 1), (1, 1),
        ]

        /// Expected row order (by id) in the **All** view for each sort field and
        /// direction. Indices below map to `Fixtures.id(_:)`; see the per-field
        /// reasoning inline.
        enum Sort {
            // saved_at increases with index → DESC is reverse index order.
            static let savedAtDescending = ids([7, 6, 5, 4, 3, 2, 1, 0]) // also the app default
            static let savedAtAscending = ids([0, 1, 2, 3, 4, 5, 6, 7])

            // read: 0=Feb01, 5=Feb10, 6=Feb15; unread {1,2,3,4,7} last by id DESC.
            static let readAtDescending = ids([6, 5, 0, 7, 4, 3, 2, 1])
            static let readAtAscending = ids([0, 5, 6, 7, 4, 3, 2, 1])

            // ratings: 0→5, 5→4, 6→3, 7→2, 3→1; zeros {1,2,4} tie, id DESC.
            static let ratingDescending = ids([0, 5, 6, 7, 3, 4, 2, 1])
            static let ratingAscending = ids([4, 2, 1, 3, 7, 6, 5, 0])

            // word_count: 2=5000,7=3200,1=2500,5=1800,0=1200,6=600,3=300; 4=NULL last.
            static let wordCountDescending = ids([2, 7, 1, 5, 0, 6, 3, 4])
            static let wordCountAscending = ids([3, 6, 0, 5, 1, 7, 2, 4])
        }

        private static func ids(_ indices: [Int]) -> [String] { indices.map(Fixtures.id) }
    }

    // ── Search terms ────────────────────────────────────────────────────────
    // Distinctive REAL words with controlled occurrence, so search journeys read
    // like real use. Each appears in exactly one article's title/body.
    enum Search {
        /// Appears only in the active Rust article (index 0).
        static let activeTerm = "ownership"
        /// Appears only in the active Swift article (index 1).
        static let swiftTerm = "concurrency"
        /// Appears only in an *archived* article (index 8): found in Archive, not in All.
        static let archivedOnlyTerm = "sabbatical"
        /// Matches nothing — reserved for the no-results / empty-state check.
        static let noResults = "zzzqxk"
        /// Diacritic-insensitive: this query matches "café" in the unicode article.
        static let diacriticQuery = "cafe"
    }

    // ── Seeded highlights ─────────────────────────────────────────────────
    // Highlight texts that appear verbatim in the kitchen-sink article's body.
    enum Highlights {
        static let articleId = Ids.kitchenSink
        static let seeded: [TestHighlight] = [
            TestHighlight(id: TestULID.make(101), text: "Local-first software keeps your data on your device."),
            TestHighlight(id: TestULID.make(102), text: "Plain files outlive the apps that created them."),
        ]
    }

    // ── Large / edge corpora ────────────────────────────────────────────────

    /// A large corpus for pagination (default 120 > the 100-row first page).
    static func bulkCorpus(count: Int = 120) -> [ArticleFixture] {
        (0..<count).map { index in
            ArticleFixture(
                id: id(index),
                url: "https://example.com/bulk/\(index)",
                title: String(format: "Bulk Article %03d", index),
                savedAt: saved(index),
                site: "example.com",
                wordCount: 100 + index,
                body: "# Bulk Article \(index)\n\nFiller body number \(index).\n"
            )
        }
    }

    /// A single article whose body exceeds the reader's ~10 MB parse guard, so
    /// the reader shows the "too large / Open in Browser" notice.
    static func oversizeArticle() -> ArticleFixture {
        let chunk = "This is filler text used to push the body past the reader size guard. "
        let target = 11 * 1024 * 1024 // ~11 MB, comfortably over the 10 MB guard
        let repeats = target / chunk.utf8.count + 1
        let body = "# Oversize Article\n\n" + String(repeating: chunk, count: repeats) + "\n"
        return ArticleFixture(
            id: Ids.oversize,
            url: "https://example.com/oversize",
            title: "Oversize Article",
            savedAt: saved(200),
            site: "example.com",
            wordCount: 1_500_000,
            body: body
        )
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// `saved_at` for a corpus index: 2026-01-01 12:00 UTC plus `index` days, so
    /// a higher index is always more recently saved.
    private static func saved(_ index: Int) -> Date {
        savedBase.addingTimeInterval(TimeInterval(index) * 86_400)
    }

    private static let savedBase = parse("2026-01-01T12:00:00Z")

    private static func readAt(_ iso: String) -> Date { parse(iso) }

    private static func parse(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else {
            fatalError("Fixtures: invalid ISO date \(iso)")
        }
        return date
    }

    // Every supported block for the deep-read journey, plus the two seeded
    // highlight sentences (verbatim) and a local asset image.
    private static let kitchenSinkBody = """
    # The Complete Markdown Sample

    Local-first software keeps your data on your device.

    ## Lists

    - First bullet
    - Second bullet

    1. First step
    2. Second step

    - [ ] Unchecked task
    - [x] Checked task

    ## Quote

    > Plain files outlive the apps that created them.

    ## Code

    ```swift
    let greeting = "hello"
    print(greeting)
    ```

    ## Table

    | Language | Year |
    | --- | --- |
    | Rust | 2010 |
    | Swift | 2014 |

    Some ~~struck-through~~ text and a [link](https://example.com).

    <div class="callout">Raw HTML block.</div>

    A sentence with a footnote.[^1]

    ![Sample image](../assets/\(Ids.kitchenSink)/\(PNGFixture.fileName))

    [^1]: The footnote text.
    """
}
