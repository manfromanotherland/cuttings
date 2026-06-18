// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Markdown

// Both SwiftUI and Markdown export `Text` and `Image`. These file-scope aliases
// make the bare names resolve to SwiftUI; Markdown's nodes are used qualified
// (`Markdown.Text`, `Markdown.Image`).
private typealias Text = SwiftUI.Text
private typealias Image = SwiftUI.Image

/// Renders a single block-level Markdown node as native SwiftUI. Container
/// blocks (lists, quotes, list items) recurse back through this view.
struct MarkdownBlockView: View {
    let block: Markup
    let theme: MarkdownTheme
    let libraryURL: URL?

    var body: some View {
        switch block {
        case let heading as Heading:
            Text(InlineRenderer.attributed(heading, theme: theme))
                .font(theme.headingFont(heading.level))
                .padding(.top, theme.bodySize * 0.5)
                .textSelection(.enabled)

        case let paragraph as Paragraph:
            ParagraphView(paragraph: paragraph, theme: theme, libraryURL: libraryURL)

        case let quote as BlockQuote:
            HStack(spacing: 12) {
                Rectangle()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: theme.blockSpacing * 0.6) {
                    ForEach(childArray(quote)) { item in
                        MarkdownBlockView(block: item.markup, theme: theme, libraryURL: libraryURL)
                    }
                }
                .foregroundStyle(.secondary)
            }

        case let list as UnorderedList:
            ListView(items: childArray(list), ordered: false, startIndex: 1,
                     theme: theme, libraryURL: libraryURL)

        case let list as OrderedList:
            ListView(items: childArray(list), ordered: true, startIndex: Int(list.startIndex),
                     theme: theme, libraryURL: libraryURL)

        case let item as ListItem:
            // Reached when recursing inside a ListView item.
            VStack(alignment: .leading, spacing: theme.blockSpacing * 0.5) {
                ForEach(childArray(item)) { child in
                    MarkdownBlockView(block: child.markup, theme: theme, libraryURL: libraryURL)
                }
            }

        case let code as CodeBlock:
            CodeBlockView(code: code.code, language: code.language, theme: theme)

        case is ThematicBreak:
            Divider().padding(.vertical, theme.blockSpacing * 0.5)

        case let table as Markdown.Table:
            MarkdownTableView(table: table, theme: theme)

        case let html as HTMLBlock:
            // Render visible text only; never raw tags.
            Text(html.rawHTML.strippingTags)
                .font(theme.bodyFont)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

        default:
            // Unknown container: recurse into children so nothing is dropped.
            VStack(alignment: .leading, spacing: theme.blockSpacing * 0.6) {
                ForEach(childArray(block)) { child in
                    MarkdownBlockView(block: child.markup, theme: theme, libraryURL: libraryURL)
                }
            }
        }
    }
}

// ── Paragraph (may contain block-level images) ──────────────────────────────

/// A paragraph is split into runs of inline text and standalone images. The
/// common Substack/Medium pattern `[![alt](img)](url)` (a link wrapping a single
/// image) is detected and rendered as an image, replacing the old
/// `unwrapLinkedImages` regex hack.
private struct ParagraphView: View {
    let paragraph: Paragraph
    let theme: MarkdownTheme
    let libraryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.blockSpacing * 0.6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let attributed):
                    Text(attributed)
                        .lineSpacing(theme.lineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .image(let source, let alt):
                    AssetImageView(source: source, alt: alt, libraryURL: libraryURL)
                }
            }
        }
    }

    private enum Segment {
        case text(AttributedString)
        case image(source: String, alt: String)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var run = AttributedString()

        func flush() {
            if !run.characters.isEmpty {
                result.append(.text(run))
                run = AttributedString()
            }
        }

        for child in paragraph.children {
            if let image = standaloneImage(child) {
                flush()
                result.append(.image(source: image.source ?? "", alt: InlineRenderer.plainText(image)))
            } else {
                run.append(InlineRenderer.inline(child, theme: theme))
            }
        }
        flush()
        return result.isEmpty ? [.text(AttributedString())] : result
    }

    /// An image either bare, or as the sole meaningful child of a link.
    private func standaloneImage(_ markup: Markup) -> Markdown.Image? {
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
}

// ── Lists ───────────────────────────────────────────────────────────────────

private struct ListView: View {
    let items: [IdentifiedMarkup]
    let ordered: Bool
    let startIndex: Int
    let theme: MarkdownTheme
    let libraryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.blockSpacing * 0.4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: index, item: item.markup)
                        .font(theme.bodyFont)
                        .foregroundStyle(.secondary)
                    MarkdownBlockView(block: item.markup, theme: theme, libraryURL: libraryURL)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for index: Int, item: Markup) -> some View {
        if let listItem = item as? ListItem, let checkbox = listItem.checkbox {
            Image(systemName: checkbox == .checked ? "checkmark.square" : "square")
        } else if ordered {
            Text("\(startIndex + index).")
                .monospacedDigit()
        } else {
            Text("•")
        }
    }
}

// ── Code block ──────────────────────────────────────────────────────────────

private struct CodeBlockView: View {
    let code: String
    let language: String?
    let theme: MarkdownTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code.hasSuffix("\n") ? String(code.dropLast()) : code)
                .font(theme.codeFont)
                .textSelection(.enabled)
                .padding(14)
        }
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// ── Table ───────────────────────────────────────────────────────────────────

private struct MarkdownTableView: View {
    let table: Markdown.Table
    let theme: MarkdownTheme

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(table.head.cells.enumerated()), id: \.offset) { _, cell in
                    Text(InlineRenderer.attributed(cell, theme: theme))
                        .font(theme.bodyFont.weight(.semibold))
                        .textSelection(.enabled)
                }
            }
            Divider()
            ForEach(Array(table.body.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        Text(InlineRenderer.attributed(cell, theme: theme))
                            .font(theme.bodyFont)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Wraps a `Markup` child with a stable identity for `ForEach`.
struct IdentifiedMarkup: Identifiable {
    let id: Int
    let markup: Markup
}

private func childArray(_ markup: Markup) -> [IdentifiedMarkup] {
    Array(markup.children).enumerated().map { IdentifiedMarkup(id: $0.offset, markup: $0.element) }
}

private extension String {
    /// Crude tag stripper for raw HTML blocks.
    var strippingTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
