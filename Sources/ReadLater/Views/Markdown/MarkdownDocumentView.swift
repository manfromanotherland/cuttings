// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Markdown

/// Native reader: parses the article Markdown with swift-markdown and renders it
/// as a SwiftUI view tree. Replaces the `WKWebView`-based `MarkdownWebView`.
/// Light/Dark adapt automatically via semantic colors (appearance is applied
/// app-wide in `ReadLaterApp`), and links open in the system browser.
struct MarkdownDocumentView: View {
    let markdown: String
    let libraryURL: URL?
    var font: ReaderFont = .system
    var fontSize: ReaderFontSize = .medium

    private let blocks: [IdentifiedMarkup]

    init(markdown: String, libraryURL: URL?,
         font: ReaderFont = .system, fontSize: ReaderFontSize = .medium) {
        self.markdown = markdown
        self.libraryURL = libraryURL
        self.font = font
        self.fontSize = fontSize
        let document = Document(parsing: Self.unwrapLinkedImages(markdown))
        self.blocks = Array(document.children).enumerated().map {
            IdentifiedMarkup(id: $0.offset, markup: $0.element)
        }
    }

    /// Collapse a link wrapping a single image — `[![alt](img)](url)`, often
    /// split across blank lines by the extension's HTML→Markdown step as
    /// `[\n\n![alt](img)\n\n](url)` — down to the bare image. When the wrapper
    /// spans blank lines CommonMark can't parse it as one link, so it would
    /// otherwise leak a literal `[` and `](url)` around the picture. The image
    /// itself is already stored locally; the outer link target is dropped.
    private static func unwrapLinkedImages(_ markdown: String) -> String {
        let pattern = #"\[\s*(!\[[^\]]*\]\([^)]*\))\s*\]\([^)]*\)"#
        return markdown.replacingOccurrences(
            of: pattern, with: "$1", options: .regularExpression)
    }

    private var theme: MarkdownTheme {
        MarkdownTheme(font: font, fontSize: fontSize)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                ForEach(blocks) { block in
                    MarkdownBlockView(block: block.markup, theme: theme, libraryURL: libraryURL)
                }
            }
            .font(theme.bodyFont)
            .frame(maxWidth: theme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 80)
        }
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }
}
