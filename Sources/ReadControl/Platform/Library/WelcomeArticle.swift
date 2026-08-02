// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Seeds a welcome article into a freshly chosen library folder.
///
/// The article body lives in `Resources/WelcomeArticle.md` so the copy can be
/// updated without touching Swift code. A pre-set highlight is written
/// alongside the article to demonstrate the highlights feature.
enum WelcomeArticle {
    private static let articleId = "01JZWC0M0000000000000001"
    private static let highlightId = "01JZWC0M0000000000000002"
    private static let highlightedText = "ReadControl keeps your articles where you can always find them."

    /// Write the welcome article into `libraryURL/articles/` only if that
    /// folder contains no `.md` files — i.e. the user picked an empty folder.
    /// Failures are silently ignored so a missing resource never blocks launch.
    static func seedIfEmpty(in libraryURL: URL) {
        let articlesURL = libraryURL.appendingPathComponent("articles", isDirectory: true)
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: articlesURL.path)) ?? []
        guard !existing.contains(where: { $0.hasSuffix(".md") }) else { return }

        guard
            let resourceURL = Bundle.main.url(forResource: "WelcomeArticle", withExtension: "md"),
            let rawBody = try? String(contentsOf: resourceURL, encoding: .utf8)
        else { return }

        let body = rawBody.trimmingCharacters(in: .newlines) + "\n"
        let articleURL = articlesURL.appendingPathComponent("\(articleId).md")
        try? articleContent(body: body).write(to: articleURL, atomically: true, encoding: .utf8)

        seedHighlight(in: libraryURL)
    }

    /// The complete article file for `body`: YAML front matter (with the hash,
    /// word count, and timestamp derived from it) followed by the body itself.
    private static func articleContent(body: String) -> String {
        let sourceHash = "sha256:" + SHA256.hash(data: Data(body.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let wordCount = body.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        let savedAt = ISO8601DateFormatter().string(from: Date())

        var content = "---\n"
        content += "format_version: 1\n"
        content += "id: \(articleId)\n"
        content += "url: https://readcontrol.app/welcome\n"
        content += "canonical_url: https://readcontrol.app/welcome\n"
        content += "title: Welcome to ReadControl\n"
        content += "author: Rodrigo Boniatti\n"
        content += "site: readcontrol.app\n"
        content += "saved_at: \(savedAt)\n"
        content += "archived: false\n"
        content += "favorite: false\n"
        content += "rating: 5\n"
        content += "tags:\n- welcome\n"
        content += "excerpt: A guide to getting started with ReadControl \u{2014} and a taste of what it can do.\n"
        content += "word_count: \(wordCount)\n"
        content += "lang: en\n"
        content += "source_hash: \(sourceHash)\n"
        content += "---\n\n"
        content += body
        return content
    }

    private static func seedHighlight(in libraryURL: URL) {
        let highlightsDir = libraryURL.appendingPathComponent("highlights", isDirectory: true)
        try? FileManager.default.createDirectory(at: highlightsDir, withIntermediateDirectories: true)
        let highlightContent = "> \(highlightedText)\n<!-- hl \(highlightId) -->\n\n"
        let highlightURL = highlightsDir.appendingPathComponent("\(articleId).md")
        try? highlightContent.write(to: highlightURL, atomically: true, encoding: .utf8)
    }
}
