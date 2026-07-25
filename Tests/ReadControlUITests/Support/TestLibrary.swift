// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An isolated, on-disk library for one test: `<tmp>/<uuid>/library/{articles,
/// assets,highlights}` with a sibling `<tmp>/<uuid>/index.db`. Fixtures written
/// here are indexed by the real app — before launch (the boot rebuild picks them
/// up) or after (exercising the FSEvents watcher). Destroyed in teardown.
final class TestLibrary {
    /// `<tmp>/<uuid>` — the per-test root holding both the library and the DB.
    let root: URL
    /// The library folder the app is pointed at (`root/library`).
    let libraryURL: URL
    /// The index DB path (`root/index.db`), kept outside the library per the contract.
    let dbURL: URL

    /// A throwaway `UserDefaults` suite name the app is pointed at for this test, so
    /// preference changes never touch the real `app.readcontrol.app` domain. Destroyed
    /// in `destroy()`.
    let defaultsSuiteName: String

    var articlesDir: URL {
        libraryURL.appendingPathComponent("articles", isDirectory: true)
    }

    var assetsDir: URL {
        libraryURL.appendingPathComponent("assets", isDirectory: true)
    }

    var highlightsDir: URL {
        libraryURL.appendingPathComponent("highlights", isDirectory: true)
    }

    init() throws {
        let id = UUID().uuidString
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadControlUITests", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        libraryURL = root.appendingPathComponent("library", isDirectory: true)
        dbURL = root.appendingPathComponent("index.db")
        defaultsSuiteName = "app.readcontrol.app.uitest.\(id)"
        for dir in [articlesDir, assetsDir, highlightsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // ── Articles ────────────────────────────────────────────────────────────

    func write(_ article: ArticleFixture) throws {
        try article.rendered().write(to: articleFileURL(id: article.id), atomically: true, encoding: .utf8)
    }

    func write(_ articles: [ArticleFixture]) throws {
        for article in articles {
            try write(article)
        }
    }

    /// Writes arbitrary file contents for `id` — for external-edit and malformed-file tests.
    func writeRaw(id: String, contents: String) throws {
        try contents.write(to: articleFileURL(id: id), atomically: true, encoding: .utf8)
    }

    func deleteArticle(id: String) throws {
        try FileManager.default.removeItem(at: articleFileURL(id: id))
    }

    func articleExists(id: String) -> Bool {
        FileManager.default.fileExists(atPath: articleFileURL(id: id).path)
    }

    /// The raw file contents for `id`, or nil if it doesn't exist.
    func articleContents(id: String) -> String? {
        try? String(contentsOf: articleFileURL(id: id), encoding: .utf8)
    }

    /// The parsed frontmatter for `id`, or nil if the file is missing/unfenced.
    func frontmatter(id: String) -> Frontmatter? {
        articleContents(id: id).flatMap(Frontmatter.init(contents:))
    }

    // ── Assets & highlights ───────────────────────────────────────────────

    func writeAsset(articleId: String, fileName: String, data: Data) throws {
        let dir = assetsDir.appendingPathComponent(articleId, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(fileName))
    }

    func writeHighlights(articleId: String, _ highlights: [TestHighlight]) throws {
        try FileManager.default.createDirectory(at: highlightsDir, withIntermediateDirectories: true)
        try HighlightsFile.render(highlights)
            .write(to: highlightsFileURL(id: articleId), atomically: true, encoding: .utf8)
    }

    func highlightsExist(articleId: String) -> Bool {
        FileManager.default.fileExists(atPath: highlightsFileURL(id: articleId).path)
    }

    /// Raw contents of a reading's highlights file, or nil if it doesn't exist.
    func highlightsContents(articleId: String) -> String? {
        try? String(contentsOf: highlightsFileURL(id: articleId), encoding: .utf8)
    }

    // ── URL accessors ─────────────────────────────────────────────────────

    func articleFileURL(id: String) -> URL {
        articlesDir.appendingPathComponent("\(id).md")
    }

    func highlightsFileURL(id: String) -> URL {
        highlightsDir.appendingPathComponent("\(id).md")
    }

    // ── Teardown ────────────────────────────────────────────────────────────

    func destroy() {
        // Drop the isolated preferences suite the app wrote to (values + backing
        // plist), then the temp library tree.
        UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
