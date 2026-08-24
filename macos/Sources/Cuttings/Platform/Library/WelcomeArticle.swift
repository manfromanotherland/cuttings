// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Seeds a welcome article into a freshly chosen library folder.
///
/// The article body lives in `Resources/WelcomeArticle.md` so the copy can be
/// updated without touching Swift code. The seed is written into the standard
/// per-reading folder (`articles/<prefix>/<id>/`) with a content-addressed id,
/// exactly like a real save — so the scanner indexes it and a later save of the
/// same URL dedupes against it. A pre-set highlight (`highlights.md`) is written
/// alongside the article to demonstrate the highlights feature.
enum WelcomeArticle {
    /// App-owned origin for the bundled welcome reading. A custom URL keeps the
    /// card self-contained until Cuttings has an official public website.
    private static let sourceURL = "cuttings://welcome"

    /// Stable identity input for the bundled reading. This is deliberately not
    /// an external page URL, so the welcome card never points at upstream content.
    private static let normalizedSourceURL = sourceURL

    /// Content-addressed id: SHA-256 (hex) of the normalized source URL, matching
    /// core's `url_id`. The reading-folder name and frontmatter `id`.
    private static let articleId = sha256Hex(normalizedSourceURL)

    private static let highlightId = "01JZWC0M0000000000000002"
    private static let highlightedText = "Cuttings keeps everything you save right where you can find it."

    /// Write the welcome article only if the library holds no readings yet —
    /// i.e. the user picked an empty folder. Failures are silently ignored so a
    /// missing resource never blocks launch.
    static func seedIfEmpty(in libraryURL: URL) {
        let articlesURL = libraryURL.appendingPathComponent("articles", isDirectory: true)
        guard !libraryHasReading(articlesURL: articlesURL) else { return }

        guard
            let resourceURL = Bundle.main.url(forResource: "WelcomeArticle", withExtension: "md"),
            let rawBody = try? String(contentsOf: resourceURL, encoding: .utf8)
        else { return }

        let body = rawBody.trimmingCharacters(in: .newlines) + "\n"
        let folder = readingFolder(in: libraryURL)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let articleURL = folder.appendingPathComponent("article.md")
        try? articleContent(body: body).write(to: articleURL, atomically: true, encoding: .utf8)

        seedHighlight(in: folder)
    }

    /// The reading's own folder: `articles/<first two chars of id>/<id>/`, the
    /// fan-out layout from the library-format spec.
    private static func readingFolder(in libraryURL: URL) -> URL {
        libraryURL
            .appendingPathComponent("articles", isDirectory: true)
            .appendingPathComponent(String(articleId.prefix(2)), isDirectory: true)
            .appendingPathComponent(articleId, isDirectory: true)
    }

    /// Whether the library already contains at least one reading: an `article.md`
    /// under any `articles/<prefix>/<id>/` folder. Walks only the two shallow
    /// fan-out levels, so choosing a populated library never re-seeds — and since
    /// the welcome article's own folder counts, it is never seeded twice.
    private static func libraryHasReading(articlesURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard let buckets = try? fileManager.contentsOfDirectory(
            at: articlesURL, includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return false
        }
        return buckets.contains { bucket in
            let isDir = (try? bucket.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return false }
            let readings = (try? fileManager.contentsOfDirectory(
                at: bucket, includingPropertiesForKeys: nil
            )) ?? []
            return readings.contains { reading in
                fileManager.fileExists(atPath: reading.appendingPathComponent("article.md").path)
            }
        }
    }

    /// The complete article file for `body`: YAML front matter (with the hash,
    /// word count, and timestamp derived from it) followed by the body itself.
    private static func articleContent(body: String) -> String {
        let sourceHash = "sha256:" + sha256Hex(body)
        let wordCount = body.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        let savedAt = ISO8601DateFormatter().string(from: Date())

        var content = "---\n"
        content += "format_version: 1\n"
        content += "id: \(articleId)\n"
        content += "url: \(sourceURL)\n"
        content += "canonical_url: \(sourceURL)\n"
        content += "title: Welcome to Cuttings\n"
        content += "author: Rodrigo Boniatti\n"
        content += "site: Cuttings\n"
        content += "saved_at: \(savedAt)\n"
        content += "archived: false\n"
        content += "favorite: false\n"
        content += "rating: 0\n"
        content += "tags:\n- welcome\n"
        content += "excerpt: A guide to getting started with Cuttings, and a taste of what it can do.\n"
        content += "word_count: \(wordCount)\n"
        content += "lang: en\n"
        content += "source_hash: \(sourceHash)\n"
        content += "---\n\n"
        content += body
        return content
    }

    private static func seedHighlight(in folder: URL) {
        let highlightContent = "> \(highlightedText)\n<!-- hl \(highlightId) -->\n\n"
        let highlightURL = folder.appendingPathComponent("highlights.md")
        try? highlightContent.write(to: highlightURL, atomically: true, encoding: .utf8)
    }

    /// SHA-256 of a string's UTF-8 bytes as lowercase hex.
    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
