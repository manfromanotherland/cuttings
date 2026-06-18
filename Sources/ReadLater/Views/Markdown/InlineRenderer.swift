// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Markdown

// `Text` collides between SwiftUI and Markdown; alias the bare name to SwiftUI
// so `Text.LineStyle` resolves. Markdown's node is used as `Markdown.Text`.
private typealias Text = SwiftUI.Text

/// Flattens swift-markdown inline nodes into a styled `AttributedString` for use
/// in a SwiftUI `Text`. Font traits (bold/italic/code) and link/strike state are
/// carried down the recursion and applied only at text leaves, so nested
/// emphasis combines correctly.
enum InlineRenderer {

    struct Style {
        var bold = false
        var italic = false
        var strike = false
        var link: URL?

        func with(bold: Bool? = nil, italic: Bool? = nil,
                  strike: Bool? = nil, link: URL? = nil) -> Style {
            var s = self
            if let bold { s.bold = bold }
            if let italic { s.italic = italic }
            if let strike { s.strike = strike }
            if let link { s.link = link }
            return s
        }
    }

    /// Build an attributed string from a block node's inline children.
    static func attributed(_ markup: Markup, theme: MarkdownTheme) -> AttributedString {
        concat(markup.children, style: Style(), theme: theme)
    }

    /// Render a single inline node (the node itself, not just its children).
    static func inline(_ markup: Markup, theme: MarkdownTheme) -> AttributedString {
        render(markup, style: Style(), theme: theme)
    }

    /// Recursively collect the visible text of a node (e.g. an image's alt text).
    static func plainText(_ markup: Markup) -> String {
        if let text = markup as? Markdown.Text { return text.string }
        if let code = markup as? InlineCode { return code.code }
        return markup.children.map { plainText($0) }.joined()
    }

    private static func concat<S: Sequence>(_ children: S, style: Style,
                                            theme: MarkdownTheme) -> AttributedString
    where S.Element == Markup {
        var out = AttributedString()
        for child in children {
            out.append(render(child, style: style, theme: theme))
        }
        return out
    }

    private static func render(_ markup: Markup, style: Style,
                               theme: MarkdownTheme) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string, attributes: container(style, theme, code: false))
        case let code as InlineCode:
            return AttributedString(code.code, attributes: container(style, theme, code: true))
        case is LineBreak:
            return AttributedString("\n")
        case is SoftBreak:
            return AttributedString(" ")
        case is InlineHTML:
            return AttributedString("")
        case let image as Markdown.Image:
            // Inline images are rendered as blocks elsewhere; here fall back to
            // the alt text so nothing is silently dropped from running text.
            let alt = plainText(image)
            return alt.isEmpty
                ? AttributedString("")
                : AttributedString(alt, attributes: container(style, theme, code: false))
        case let emphasis as Emphasis:
            return concat(emphasis.children, style: style.with(italic: true), theme: theme)
        case let strong as Strong:
            return concat(strong.children, style: style.with(bold: true), theme: theme)
        case let strike as Strikethrough:
            return concat(strike.children, style: style.with(strike: true), theme: theme)
        case let link as Markdown.Link:
            var s = style
            if let dest = link.destination, let url = URL(string: dest) { s.link = url }
            return concat(link.children, style: s, theme: theme)
        default:
            return concat(markup.children, style: style, theme: theme)
        }
    }

    private static func container(_ style: Style, _ theme: MarkdownTheme,
                                  code: Bool) -> AttributeContainer {
        var c = AttributeContainer()
        var font = code
            ? Font.system(size: theme.bodySize * 0.9, design: .monospaced)
            : Font.system(size: theme.bodySize, design: theme.design)
        if style.bold { font = font.bold() }
        if style.italic { font = font.italic() }
        c.font = font
        // Use explicit Text.LineStyle values so the attribute resolves to the
        // SwiftUI scope (a bare `.single` is ambiguous with Foundation's
        // NSUnderlineStyle).
        if style.strike { c.strikethroughStyle = Text.LineStyle(pattern: .solid, color: nil) }
        if code { c.backgroundColor = Color.secondary.opacity(0.15) }
        if let link = style.link {
            c.link = link
            c.foregroundColor = .accentColor
            c.underlineStyle = Text.LineStyle(pattern: .solid, color: nil)
        }
        return c
    }
}
