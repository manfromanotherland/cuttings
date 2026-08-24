// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A presentation snapshot of one saved highlight, kept apart from the
/// `FfiHighlight` boundary DTO so feature code and app state speak app language
/// rather than "this came from the Rust FFI" (see ADR 0001). Mirrors the
/// boundary fields exactly. The rendered row view is `HighlightRowView`.
struct HighlightRow: Identifiable, Equatable, Sendable {
    var id: String
    var text: String
}

extension HighlightRow {
    init(_ highlight: FfiHighlight) {
        id = highlight.id
        text = highlight.text
    }
}
