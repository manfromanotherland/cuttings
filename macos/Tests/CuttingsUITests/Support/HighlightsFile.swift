// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A single fake highlight: a stable id and the verbatim highlighted text.
struct TestHighlight {
    var id: String
    var text: String
}

/// Renders `highlights/<id>.md` in the core's exact format (`core/src/highlights.rs`):
/// each highlight is one `> `-prefixed line per text line (a bare `>` for an
/// empty line), terminated by `<!-- hl <id> -->` and a blank line.
enum HighlightsFile {
    static func render(_ highlights: [TestHighlight]) -> String {
        var out = ""
        for highlight in highlights {
            if highlight.text.isEmpty {
                out += ">\n"
            } else {
                // `components(separatedBy:)` preserves empty lines, matching the
                // core's `split('\n')`.
                for line in highlight.text.components(separatedBy: "\n") {
                    out += "> \(line)\n"
                }
            }
            out += "<!-- hl \(highlight.id) -->\n\n"
        }
        return out
    }
}
