// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CryptoKit

/// A single fake reading, rendered to the exact on-disk format the Rust core
/// parses (`core/src/frontmatter.rs` + `types.rs`): YAML frontmatter followed by
/// a Markdown body. Required fields are always emitted; optional fields only
/// when set, matching the core's `#[serde(skip_serializing_if = "Option::is_none")]`
/// and `#[serde(default)]` rules.
struct ArticleFixture {
    // Required frontmatter.
    var id: String
    var url: String
    var canonicalURL: String
    var title: String
    var savedAt: Date
    var archived: Bool
    var favorite: Bool
    var tags: [String]

    // Optional frontmatter — emitted only when non-nil / non-zero.
    /// Presence marks the reading read (there is no separate `read` boolean).
    var readAt: Date?
    /// 0 means unrated; only emitted when > 0 (the core defaults a missing key to 0).
    var rating: UInt8
    var author: String?
    var site: String?
    var excerpt: String?
    var wordCount: Int?
    var lang: String?

    /// The Markdown body (the `# Title` heading + content).
    var body: String

    init(
        id: String,
        url: String,
        title: String,
        savedAt: Date,
        canonicalURL: String? = nil,
        archived: Bool = false,
        favorite: Bool = false,
        tags: [String] = [],
        readAt: Date? = nil,
        rating: UInt8 = 0,
        author: String? = nil,
        site: String? = nil,
        excerpt: String? = nil,
        wordCount: Int? = nil,
        lang: String? = nil,
        body: String? = nil
    ) {
        self.id = id
        self.url = url
        self.canonicalURL = canonicalURL ?? url
        self.title = title
        self.savedAt = savedAt
        self.archived = archived
        self.favorite = favorite
        self.tags = tags
        self.readAt = readAt
        self.rating = rating
        self.author = author
        self.site = site
        self.excerpt = excerpt
        self.wordCount = wordCount
        self.lang = lang
        self.body = body ?? "# \(title)\n\nBody of \(title).\n"
    }

    /// `sha256:<hex>` over the body bytes. The scanner also keys on file mtime,
    /// so an exact match with the core isn't required for indexing — but this
    /// produces a spec-valid `source_hash`.
    var sourceHash: String { "sha256:" + Self.sha256Hex(body) }

    /// The full file contents: frontmatter fence, fields, fence, blank line, body.
    func rendered() -> String {
        var lines: [String] = []
        lines.append("format_version: 1")
        lines.append("id: \(quoted(id))")
        lines.append("url: \(quoted(url))")
        lines.append("canonical_url: \(quoted(canonicalURL))")
        lines.append("title: \(quoted(title))")
        if let author { lines.append("author: \(quoted(author))") }
        if let site { lines.append("site: \(quoted(site))") }
        lines.append("saved_at: \(quoted(Self.timestamp(savedAt)))")
        if let readAt { lines.append("read_at: \(quoted(Self.timestamp(readAt)))") }
        lines.append("archived: \(archived)")
        lines.append("favorite: \(favorite)")
        if rating > 0 { lines.append("rating: \(rating)") }
        lines.append("tags: [\(tags.map(quoted).joined(separator: ", "))]")
        if let excerpt { lines.append("excerpt: \(quoted(excerpt))") }
        if let wordCount { lines.append("word_count: \(wordCount)") }
        if let lang { lines.append("lang: \(quoted(lang))") }
        lines.append("source_hash: \(quoted(sourceHash))")

        let frontmatter = lines.map { $0 + "\n" }.joined()
        let normalizedBody = body.hasSuffix("\n") ? body : body + "\n"
        return "---\n" + frontmatter + "---\n\n" + normalizedBody
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// A YAML double-quoted scalar. Quoting every string value keeps titles with
    /// colons/emoji, `sha256:` hashes, and ISO timestamps unambiguous for the
    /// core's YAML parser.
    private func quoted(_ string: String) -> String {
        var escaped = ""
        for character in string {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    /// ISO-8601 UTC with millisecond precision — the format the core documents
    /// for `saved_at` / `read_at`, chosen so lexicographic order == chronological.
    static func timestamp(_ date: Date) -> String { isoFormatter.string(from: date) }

    static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
