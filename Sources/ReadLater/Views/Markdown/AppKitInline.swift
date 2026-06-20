// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Markdown

/// Flattens swift-markdown inline nodes into an `NSAttributedString` with AppKit
/// fonts and colors. This mirrors `InlineRenderer` (which targets SwiftUI's
/// `Text`), but emits `NSFont`/`NSColor` directly because SwiftUI's opaque
/// `Font` does not bridge reliably into an `NSAttributedString` — headings and
/// emphasis would silently fall back to the default system font. Used by the
/// `NSTextView`-backed reader runs (see `SelectableTextView`).
enum AppKitInline {

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

    /// Build an attributed string from a block node's inline children. `weight`
    /// and `size` set the base run; emphasis (bold/italic/code) layers on top.
    static func attributed(_ markup: Markup, size: CGFloat, weight: Font.Weight,
                           design: Font.Design, color: NSColor = .labelColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children {
            out.append(render(child, style: Style(), size: size,
                              weight: weight, design: design, color: color))
        }
        return out
    }

    private static func render(_ markup: Markup, style: Style, size: CGFloat,
                               weight: Font.Weight, design: Font.Design,
                               color: NSColor) -> NSAttributedString {
        switch markup {
        case let text as Markdown.Text:
            return leaf(text.string, style: style, size: size, weight: weight,
                        design: design, color: color, code: false)
        case let code as InlineCode:
            return leaf(code.code, style: style, size: size, weight: weight,
                        design: design, color: color, code: true)
        case is LineBreak:
            return NSAttributedString(string: "\n")
        case is SoftBreak:
            return NSAttributedString(string: " ")
        case is InlineHTML:
            return NSAttributedString(string: "")
        case let image as Markdown.Image:
            // Inline images fall back to alt text so nothing is dropped; block
            // images are handled by the SwiftUI renderer outside the text run.
            let alt = InlineRenderer.plainText(image)
            return alt.isEmpty
                ? NSAttributedString()
                : leaf(alt, style: style, size: size, weight: weight,
                       design: design, color: color, code: false)
        case let emphasis as Emphasis:
            return concat(emphasis.children, style: style.with(italic: true),
                          size: size, weight: weight, design: design, color: color)
        case let strong as Strong:
            return concat(strong.children, style: style.with(bold: true),
                          size: size, weight: weight, design: design, color: color)
        case let strike as Strikethrough:
            return concat(strike.children, style: style.with(strike: true),
                          size: size, weight: weight, design: design, color: color)
        case let link as Markdown.Link:
            var s = style
            if let dest = link.destination, let url = URL(string: dest) { s.link = url }
            return concat(link.children, style: s, size: size,
                          weight: weight, design: design, color: color)
        default:
            return concat(markup.children, style: style, size: size,
                          weight: weight, design: design, color: color)
        }
    }

    private static func concat<S: Sequence>(_ children: S, style: Style, size: CGFloat,
                                            weight: Font.Weight, design: Font.Design,
                                            color: NSColor) -> NSAttributedString
    where S.Element == Markup {
        let out = NSMutableAttributedString()
        for child in children {
            out.append(render(child, style: style, size: size,
                              weight: weight, design: design, color: color))
        }
        return out
    }

    private static func leaf(_ string: String, style: Style, size: CGFloat,
                             weight: Font.Weight, design: Font.Design,
                             color: NSColor, code: Bool) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [:]
        attrs[.font] = makeFont(size: code ? size * 0.9 : size, weight: weight,
                                design: code ? .monospaced : design,
                                bold: style.bold, italic: style.italic)
        attrs[.foregroundColor] = color
        if style.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if code { attrs[.backgroundColor] = NSColor.secondaryLabelColor.withAlphaComponent(0.15) }
        if let link = style.link {
            attrs[.link] = link
            attrs[.foregroundColor] = NSColor.controlAccentColor
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: string, attributes: attrs)
    }

    /// Build a system font at `size`/`weight`/`design`, then layer bold/italic
    /// symbolic traits so nested emphasis composes (matching `InlineRenderer`).
    static func makeFont(size: CGFloat, weight: Font.Weight, design: Font.Design,
                         bold: Bool, italic: Bool) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
        var descriptor = fallback.fontDescriptor
        if let designed = descriptor.withDesign(design.systemDesign) { descriptor = designed }
        var traits = descriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        descriptor = descriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? fallback
    }
}

// ── SwiftUI → AppKit mappings ────────────────────────────────────────────────

extension Font.Weight {
    /// Map the SwiftUI weights the theme uses onto AppKit font weights.
    var nsWeight: NSFont.Weight {
        if self == .ultraLight { return .ultraLight }
        if self == .thin { return .thin }
        if self == .light { return .light }
        if self == .medium { return .medium }
        if self == .semibold { return .semibold }
        if self == .bold { return .bold }
        if self == .heavy { return .heavy }
        if self == .black { return .black }
        return .regular
    }
}

extension Font.Design {
    var systemDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        default: return .default
        }
    }
}
