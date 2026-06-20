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
///
/// Every run gets an explicit `.font` attribute, which **overrides** any
/// `.font()` view modifier on the enclosing `Text`. The base font therefore has
/// to be injected here via `FontContext` — passing a heading's size/weight so
/// headings actually render as headings rather than inheriting body text.
enum InlineRenderer {

    /// The base font a run inherits before inline emphasis (bold/italic/code) is
    /// layered on top. Callers pass `.body` for running text or `.heading(...)`
    /// / a custom context for headings and table headers.
    struct FontContext {
        var size: CGFloat
        var weight: Font.Weight = .regular
        var design: Font.Design = .default

        static func body(_ theme: MarkdownTheme) -> FontContext {
            FontContext(size: theme.bodySize, weight: .regular, design: theme.design)
        }

        static func heading(_ level: Int, _ theme: MarkdownTheme) -> FontContext {
            FontContext(size: theme.headingSize(level),
                        weight: theme.headingWeight(level),
                        design: theme.design)
        }

        static func emphasized(_ theme: MarkdownTheme, weight: Font.Weight) -> FontContext {
            FontContext(size: theme.bodySize, weight: weight, design: theme.design)
        }
    }

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
    /// `context` defaults to the body font; headings/table headers pass their own.
    static func attributed(_ markup: Markup, theme: MarkdownTheme,
                           context: FontContext? = nil) -> AttributedString {
        concat(markup.children, style: Style(),
               context: context ?? .body(theme), theme: theme)
    }

    /// Render a single inline node (the node itself, not just its children).
    static func inline(_ markup: Markup, theme: MarkdownTheme,
                       context: FontContext? = nil) -> AttributedString {
        render(markup, style: Style(), context: context ?? .body(theme), theme: theme)
    }

    /// Recursively collect the visible text of a node (e.g. an image's alt text).
    static func plainText(_ markup: Markup) -> String {
        if let text = markup as? Markdown.Text { return text.string }
        if let code = markup as? InlineCode { return code.code }
        return markup.children.map { plainText($0) }.joined()
    }

    private static func concat<S: Sequence>(_ children: S, style: Style,
                                            context: FontContext,
                                            theme: MarkdownTheme) -> AttributedString
    where S.Element == Markup {
        var out = AttributedString()
        for child in children {
            out.append(render(child, style: style, context: context, theme: theme))
        }
        return out
    }

    private static func render(_ markup: Markup, style: Style,
                               context: FontContext,
                               theme: MarkdownTheme) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string, attributes: container(style, context, theme, code: false))
        case let code as InlineCode:
            return AttributedString(code.code, attributes: container(style, context, theme, code: true))
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
                : AttributedString(alt, attributes: container(style, context, theme, code: false))
        case let emphasis as Emphasis:
            return concat(emphasis.children, style: style.with(italic: true), context: context, theme: theme)
        case let strong as Strong:
            return concat(strong.children, style: style.with(bold: true), context: context, theme: theme)
        case let strike as Strikethrough:
            return concat(strike.children, style: style.with(strike: true), context: context, theme: theme)
        case let link as Markdown.Link:
            var s = style
            if let dest = link.destination, let url = URL(string: dest) { s.link = url }
            return concat(link.children, style: s, context: context, theme: theme)
        default:
            return concat(markup.children, style: style, context: context, theme: theme)
        }
    }

    private static func container(_ style: Style, _ ctx: FontContext,
                                  _ theme: MarkdownTheme, code: Bool) -> AttributeContainer {
        var c = AttributeContainer()
        // Start from the context's base font (body size, or a heading's size and
        // weight) then layer inline emphasis on top so nested styles compose.
        var font = code
            ? Font.system(size: ctx.size * 0.9, design: .monospaced).weight(ctx.weight)
            : Font.system(size: ctx.size, design: ctx.design).weight(ctx.weight)
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
