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
    /// Verbatim text of the reading's highlights; each occurrence is tinted.
    var highlights: [String] = []
    /// Called with the selected text when the user highlights a passage.
    var onHighlight: (String) -> Void = { _ in }

    private let groups: [RenderGroup]

    init(markdown: String, libraryURL: URL?,
         font: ReaderFont = .system, fontSize: ReaderFontSize = .medium,
         highlights: [String] = [], onHighlight: @escaping (String) -> Void = { _ in }) {
        self.markdown = markdown
        self.libraryURL = libraryURL
        self.font = font
        self.fontSize = fontSize
        self.highlights = highlights
        self.onHighlight = onHighlight
        let document = Document(parsing: Self.unwrapLinkedImages(markdown))
        self.groups = Self.makeGroups(Array(document.children))
    }

    /// A render unit: either a run of contiguous text blocks rendered as one
    /// selectable `NSTextView`, or a single non-text block (image, list, quote,
    /// table, code) rendered by the SwiftUI block renderer. Selection is
    /// continuous *within* a text run; non-text blocks form a seam.
    private enum RenderGroup: Identifiable {
        case textRun(id: Int, blocks: [Markup])
        case other(IdentifiedMarkup)

        var id: Int {
            switch self {
            case .textRun(let id, _): id
            case .other(let item): item.id
            }
        }
    }

    /// Group the document's top-level blocks, merging maximal runs of foldable
    /// (text-only) blocks. A run's id is the offset of its first block, which is
    /// distinct from every standalone block's offset, so ids stay unique.
    private static func makeGroups(_ blocks: [Markup]) -> [RenderGroup] {
        var groups: [RenderGroup] = []
        var run: [Markup] = []
        var runStart = 0

        func flush() {
            if !run.isEmpty {
                groups.append(.textRun(id: runStart, blocks: run))
                run = []
            }
        }

        for (offset, block) in blocks.enumerated() {
            if isFoldable(block) {
                if run.isEmpty { runStart = offset }
                run.append(block)
            } else {
                flush()
                groups.append(.other(IdentifiedMarkup(id: offset, markup: block)))
            }
        }
        flush()
        return groups
    }

    /// Headings and text-only paragraphs fold into a selectable text run.
    ///
    /// Lists and block quotes are intentionally *not* folded: their attributed
    /// layout (right-aligned marker tab stops, hanging indents, quote bars) is
    /// fragile inside a single large `NSTextView` and was observed to collapse
    /// the run on list-heavy, image-free articles. They render via their proven
    /// SwiftUI block views instead, forming a selection seam. (The list/quote
    /// emitters in `MarkdownTextRun` remain for a future, on-device-tested
    /// re-enable.)
    private static func isFoldable(_ block: Markup) -> Bool {
        if block is Heading { return true }
        if let paragraph = block as? Paragraph {
            return !paragraph.children.contains { standaloneImage($0) != nil }
        }
        return false
    }

    /// Mirrors `ParagraphView.standaloneImage`: a bare image, or a link wrapping
    /// a single image. Such paragraphs render as figures, not text.
    private static func standaloneImage(_ markup: Markup) -> Markdown.Image? {
        if let image = markup as? Markdown.Image { return image }
        if let link = markup as? Markdown.Link {
            let children = Array(link.children)
            let images = children.compactMap { $0 as? Markdown.Image }
            let meaningful = children.filter { child in
                if let text = child as? Markdown.Text {
                    return !text.string.trimmingCharacters(in: .whitespaces).isEmpty
                }
                return true
            }
            if images.count == 1, meaningful.count == 1 { return images.first }
        }
        return nil
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
                ForEach(groups) { group in
                    switch group {
                    case .textRun(_, let blocks):
                        SelectableTextView(
                            attributed: MarkdownTextRun.attributed(blocks, theme: theme),
                            highlights: highlights,
                            onHighlight: onHighlight
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    case .other(let item):
                        MarkdownBlockView(block: item.markup, theme: theme, libraryURL: libraryURL)
                    }
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
