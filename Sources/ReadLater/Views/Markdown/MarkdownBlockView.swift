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
    /// Verbatim highlight strings and the highlight callback, threaded to the
    /// `SelectableTextView`s that back lists, block quotes, and image captions so
    /// those blocks get the same highlight tint and Highlight/Look Up menu as
    /// body-text runs.
    var highlights: [String] = []
    var onHighlight: (String) -> Void = { _ in }

    var body: some View {
        switch block {
        case let heading as Heading:
            HeadingView(heading: heading, theme: theme)

        case let paragraph as Paragraph:
            ParagraphView(paragraph: paragraph, theme: theme, libraryURL: libraryURL,
                          highlights: highlights, onHighlight: onHighlight)

        case let quote as BlockQuote:
            // Reached only for image-bearing quotes — image-free quotes fold into
            // a shared text run (see `ArticleDocument.isFoldable`). Rendered as
            // SwiftUI so the embedded image lays out as a figure; the highlight
            // plumbing reaches any figure captions inside.
            HStack(spacing: theme.quoteBarGap) {
                RoundedRectangle(cornerRadius: theme.quoteBarWidth / 2)
                    .fill(.secondary.opacity(0.4))
                    .frame(width: theme.quoteBarWidth)
                VStack(alignment: .leading, spacing: theme.quoteInnerSpacing) {
                    ForEach(childArray(quote)) { item in
                        MarkdownBlockView(block: item.markup, theme: theme, libraryURL: libraryURL,
                                          highlights: highlights, onHighlight: onHighlight)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case let list as UnorderedList:
            // Reached only for image-bearing lists — image-free lists fold into a
            // shared text run (see `ArticleDocument.isFoldable`). SwiftUI keeps the
            // embedded figures.
            ListView(items: childArray(list), ordered: false, startIndex: 1,
                     depth: 0, theme: theme, libraryURL: libraryURL)

        case let list as OrderedList:
            ListView(items: childArray(list), ordered: true, startIndex: Int(list.startIndex),
                     depth: 0, theme: theme, libraryURL: libraryURL)

        case let item as ListItem:
            // Reached only if a ListItem is rendered outside a ListView; lists
            // normally route item content through `ListItemContent`.
            ListItemContent(item: item, depth: 0, theme: theme, libraryURL: libraryURL)

        case let code as CodeBlock:
            CodeBlockView(code: code.code, language: code.language, theme: theme)

        case is ThematicBreak:
            Divider().padding(.vertical, theme.ruleSpacing)

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
                    MarkdownBlockView(block: child.markup, theme: theme, libraryURL: libraryURL,
                                      highlights: highlights, onHighlight: onHighlight)
                }
            }
        }
    }
}

// ── Heading ─────────────────────────────────────────────────────────────────

/// A heading rendered with its own size/weight (injected via `FontContext`, so
/// the heading font is not overridden by the per-run body font), extra space
/// above to mark a section break, and level-6 styled as a muted uppercase
/// eyebrow.
private struct HeadingView: View {
    let heading: Heading
    let theme: MarkdownTheme

    var body: some View {
        content
            .padding(.top, theme.headingSpaceAbove(heading.level))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        let level = heading.level
        if theme.headingIsEyebrow(level) {
            Text(InlineRenderer.plainText(heading).uppercased())
                .font(theme.headingFont(level))
                .tracking(theme.headingTracking(level))
                .foregroundStyle(.secondary)
        } else {
            Text(InlineRenderer.attributed(heading, theme: theme,
                                           context: .heading(level, theme)))
                .tracking(theme.headingTracking(level))
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
    var highlights: [String] = []
    var onHighlight: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.blockSpacing * 0.6) {
            ForEach(segments) { identified in
                switch identified.segment {
                case .text(let attributed):
                    Text(attributed)
                        .lineSpacing(theme.lineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .image(let source, let alt):
                    AssetImageView(source: source, alt: alt, libraryURL: libraryURL, theme: theme,
                                   highlights: highlights, onHighlight: onHighlight)
                }
            }
        }
    }

    private enum Segment {
        case text(AttributedString)
        case image(source: String, alt: String)
    }

    /// A segment tagged with a source-derived id (the child it began at), so a
    /// paragraph's runs and images keep stable identity instead of keying on
    /// their position in the segment array.
    private struct IdentifiedSegment: Identifiable {
        let id: String
        let segment: Segment
    }

    private var segments: [IdentifiedSegment] {
        var result: [IdentifiedSegment] = []
        var run = AttributedString()
        var runID: String?

        func flush() {
            guard !run.characters.isEmpty else { return }
            result.append(IdentifiedSegment(id: runID ?? "#\(result.count)", segment: .text(run)))
            run = AttributedString()
            runID = nil
        }

        for (offset, child) in paragraph.children.enumerated() {
            if let image = standaloneImage(child) {
                flush()
                result.append(IdentifiedSegment(
                    id: IdentifiedMarkup.stableID(for: child, fallbackIndex: offset),
                    segment: .image(source: image.source ?? "", alt: InlineRenderer.plainText(image))))
            } else {
                // The run inherits the id of the first child that feeds it.
                if run.characters.isEmpty { runID = IdentifiedMarkup.stableID(for: child, fallbackIndex: offset) }
                run.append(InlineRenderer.inline(child, theme: theme))
            }
        }
        flush()
        return result.isEmpty
            ? [IdentifiedSegment(id: "#0", segment: .text(AttributedString()))]
            : result
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

/// An ordered or unordered list. `depth` drives the bullet glyph and lets
/// nested lists indent consistently. Item content is rendered by
/// `ListItemContent`, which recurses into nested lists with `depth + 1`.
private struct ListView: View {
    let items: [IdentifiedMarkup]
    let ordered: Bool
    let startIndex: Int
    var depth: Int = 0
    let theme: MarkdownTheme
    let libraryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.listItemSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: theme.listMarkerGap) {
                    marker(for: index, item: item.markup)
                        .font(theme.bodyFont)
                        .foregroundStyle(.secondary)
                        .frame(width: theme.listMarkerWidth(ordered: ordered), alignment: .trailing)
                    ListItemContent(item: item.markup, depth: depth,
                                    theme: theme, libraryURL: libraryURL)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for index: Int, item: Markup) -> some View {
        if let listItem = item as? ListItem, let checkbox = listItem.checkbox {
            Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checkbox == .checked ? Color.accentColor : Color.secondary)
        } else if ordered {
            Text("\(startIndex + index).")
                .monospacedDigit()
        } else {
            Text(theme.bullet(depth: depth))
        }
    }
}

/// The content of one list item: its paragraphs/blocks, plus any nested lists
/// rendered one level deeper so the bullet style and indentation step down.
private struct ListItemContent: View {
    let item: Markup
    let depth: Int
    let theme: MarkdownTheme
    let libraryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.blockSpacing * 0.5) {
            ForEach(childArray(item)) { child in
                switch child.markup {
                case let list as UnorderedList:
                    ListView(items: childArray(list), ordered: false, startIndex: 1,
                             depth: depth + 1, theme: theme, libraryURL: libraryURL)
                case let list as OrderedList:
                    ListView(items: childArray(list), ordered: true,
                             startIndex: Int(list.startIndex), depth: depth + 1,
                             theme: theme, libraryURL: libraryURL)
                default:
                    MarkdownBlockView(block: child.markup, theme: theme, libraryURL: libraryURL)
                }
            }
        }
    }
}

// ── Code block ──────────────────────────────────────────────────────────────

/// A fenced/indented code block. When a language is declared it's shown as a
/// small label above the scrollable, monospaced code surface.
private struct CodeBlockView: View {
    let code: String
    let language: String?
    let theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language.lowercased())
                    .font(theme.captionFont)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, theme.codePadding)
                    .padding(.top, theme.codePadding * 0.6)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.hasSuffix("\n") ? String(code.dropLast()) : code)
                    .font(theme.codeFont)
                    .textSelection(.enabled)
                    .padding(theme.codePadding)
            }
        }
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: theme.codeCornerRadius))
    }
}

// ── Table ───────────────────────────────────────────────────────────────────

private struct MarkdownTableView: View {
    let table: Markdown.Table
    let theme: MarkdownTheme

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                // Cells/rows carry a unique source `range`; key on it so identity
                // is content-derived rather than the column/row position.
                ForEach(Array(table.head.cells.enumerated()), id: \.element.range) { index, cell in
                    Text(InlineRenderer.attributed(cell, theme: theme,
                                                   context: .emphasized(theme, weight: .semibold)))
                        .textSelection(.enabled)
                        .gridColumnAlignment(alignment(index))
                }
            }
            Divider()
            ForEach(Array(table.body.rows.enumerated()), id: \.element.range) { _, row in
                GridRow {
                    ForEach(Array(row.cells.enumerated()), id: \.element.range) { _, cell in
                        Text(InlineRenderer.attributed(cell, theme: theme))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Map a column's Markdown alignment onto a SwiftUI grid alignment.
    private func alignment(_ index: Int) -> HorizontalAlignment {
        guard index < table.columnAlignments.count else { return .leading }
        switch table.columnAlignments[index] {
        case .some(.center): return .center
        case .some(.right): return .trailing
        default: return .leading
        }
    }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Wraps a `Markup` child with a stable identity for `ForEach`.
struct IdentifiedMarkup: Identifiable {
    let id: String
    let markup: Markup

    /// A stable identity for a parsed node, taken from its span in the *source*
    /// text rather than its index in a rendered array. `Document(parsing:)`
    /// assigns every node a unique source range, so sibling nodes never share a
    /// start location; the index fallback (only reached for nodes without range
    /// info, e.g. programmatically built ones) stays unique within its
    /// collection. Position-based ids (`\.offset`) instead reset per-row state
    /// on any insert/reorder — harmless for immutable parsed content, but this
    /// keeps identity content-derived per the list-identity rule.
    static func stableID(for markup: Markup, fallbackIndex index: Int) -> String {
        if let start = markup.range?.lowerBound {
            return "\(start.line):\(start.column)"
        }
        return "#\(index)"
    }
}

private func childArray(_ markup: Markup) -> [IdentifiedMarkup] {
    Array(markup.children).enumerated().map {
        IdentifiedMarkup(id: IdentifiedMarkup.stableID(for: $0.element, fallbackIndex: $0.offset),
                         markup: $0.element)
    }
}

private extension String {
    /// Crude tag stripper for raw HTML blocks.
    var strippingTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
