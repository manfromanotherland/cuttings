// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A minimal, dependency-free reader for an article file's frontmatter, so a
/// test can assert on-disk truth after a mutation (the project's "files are the
/// source of truth" principle). It only needs the mutable fields the journeys
/// check — `read_at`, `archived`, `favorite`, `rating`, `tags` — so it parses
/// line-by-line rather than pulling in a YAML dependency.
struct Frontmatter {
    /// Raw scalar text per key (values keep their surrounding quotes, if any).
    private let fields: [String: String]

    /// Parses the frontmatter block, or returns nil if the file has no fence yet
    /// (e.g. a mid-write read).
    init?(contents: String) {
        guard contents.hasPrefix("---\n") else { return nil }
        let afterOpen = contents.dropFirst("---\n".count)
        guard let fence = afterOpen.range(of: "\n---\n") else { return nil }
        let block = afterOpen[..<fence.lowerBound]

        var parsed: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: true) {
            // The key is everything before the first colon; keys never contain
            // one, so values with colons (URLs, timestamps, `sha256:`) are safe.
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            parsed[key] = value
        }
        fields = parsed
    }

    // ── Accessors ─────────────────────────────────────────────────────────

    /// The `read_at` timestamp, or nil when the field is absent (unread).
    var readAt: String? { fields["read_at"].map(Self.unquote) }

    /// Whether the reading is read (presence of `read_at`).
    var isRead: Bool { fields["read_at"] != nil }

    var archived: Bool { fields["archived"] == "true" }
    var favorite: Bool { fields["favorite"] == "true" }

    /// Star rating; a missing field means 0 (unrated).
    var rating: Int { Int(fields["rating"] ?? "0") ?? 0 }

    /// Tags parsed from the inline flow sequence (`["a", "b"]` / `[]`).
    var tags: [String] {
        guard let raw = fields["tags"] else { return [] }
        let inner = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if inner.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return inner.split(separator: ",").map { Self.unquote($0.trimmingCharacters(in: .whitespaces)) }
    }

    var title: String? { fields["title"].map(Self.unquote) }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// Strips surrounding double quotes and undoes the escapes `ArticleFixture`
    /// emits. Plain (unquoted) scalars pass through unchanged.
    private static func unquote(_ scalar: String) -> String {
        guard scalar.count >= 2, scalar.hasPrefix("\""), scalar.hasSuffix("\"") else { return scalar }
        return String(scalar.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
