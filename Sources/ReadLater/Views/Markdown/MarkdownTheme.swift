// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Derives every font, size, weight, and spacing value for the native Markdown
/// reader from the user's typography settings. The scale follows Apple's
/// Human Interface Guidelines: a clear six-level heading hierarchy, a generous
/// reading measure (~680 pt), and asymmetric section spacing (more room above a
/// heading than below it, so a heading binds to the text it introduces).
///
/// All values are expressed *relative to the body size* so the whole document
/// rescales when the reader picks Small … Extra Large. See DESIGN.md →
/// "Apple platform style guide" for the rationale behind each token.
struct MarkdownTheme {
    let font: ReaderFont
    let fontSize: ReaderFontSize

    var design: Font.Design { font.design }
    var bodySize: CGFloat { fontSize.points }

    // ── Reading rhythm ──────────────────────────────────────────────────────

    /// SwiftUI `lineSpacing` is the gap *between* lines, added on top of the
    /// natural (~1.2×) line height. (1.75 − 1.2) ≈ 0.55 approximates a
    /// comfortable `line-height: 1.75` reading measure.
    var lineSpacing: CGFloat { bodySize * 0.55 }

    /// Vertical gap between top-level blocks (~1em). Headings add extra space
    /// *above* themselves on top of this (see `headingSpaceAbove`).
    var blockSpacing: CGFloat { bodySize }

    /// Optimal line length for sustained reading (~60–75 characters).
    var contentMaxWidth: CGFloat { 680 }

    var bodyFont: Font { .system(size: bodySize, design: design) }
    var codeFont: Font { .system(size: bodySize * 0.9, design: .monospaced) }

    // ── Headings ────────────────────────────────────────────────────────────
    // A modular type scale. Every one of the six levels is visually distinct:
    // levels 1–2 are bold display sizes, 3–5 are semibold sub-headings, and
    // level 6 is a small uppercase "eyebrow" in a muted color.

    func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: bodySize * 1.80
        case 2: bodySize * 1.45
        case 3: bodySize * 1.20
        case 4: bodySize * 1.05
        case 5: bodySize * 0.95
        default: bodySize * 0.85   // h6 — eyebrow/overline
        }
    }

    func headingWeight(_ level: Int) -> Font.Weight {
        switch level {
        case 1, 2: .bold
        default: .semibold
        }
    }

    func headingFont(_ level: Int) -> Font {
        .system(size: headingSize(level), design: design).weight(headingWeight(level))
    }

    /// Tracking (letter-spacing). Apple tightens large display titles and opens
    /// up small uppercase labels for legibility.
    func headingTracking(_ level: Int) -> CGFloat {
        switch level {
        case 1: -0.5
        case 2: -0.3
        case 6: 0.6
        default: 0
        }
    }

    /// Level 6 is rendered as a small uppercase eyebrow in secondary color.
    func headingIsEyebrow(_ level: Int) -> Bool { level >= 6 }

    /// Space *above* a heading. Larger for higher levels so major sections get a
    /// clear visual break; this is added on top of the inter-block `blockSpacing`.
    func headingSpaceAbove(_ level: Int) -> CGFloat {
        switch level {
        case 1: bodySize * 1.7
        case 2: bodySize * 1.3
        case 3: bodySize * 1.0
        case 4: bodySize * 0.8
        default: bodySize * 0.6
        }
    }

    // ── Lists ───────────────────────────────────────────────────────────────

    /// Gap between sibling list items (tighter than `blockSpacing`).
    var listItemSpacing: CGFloat { bodySize * 0.5 }
    /// Gap between the marker (bullet/number) and the item text.
    var listMarkerGap: CGFloat { bodySize * 0.5 }
    /// Reserved width for the marker column, giving a clean hanging indent.
    /// Wide enough for a two-digit ordinal or a checkbox glyph without clipping.
    func listMarkerWidth(ordered: Bool) -> CGFloat { bodySize * (ordered ? 1.5 : 1.1) }

    /// Bullet glyph for unordered lists, cycling by nesting depth.
    func bullet(depth: Int) -> String {
        switch depth % 3 {
        case 0: "•"
        case 1: "◦"
        default: "▪"
        }
    }

    // ── Block quote ─────────────────────────────────────────────────────────

    var quoteBarWidth: CGFloat { 3 }
    var quoteBarGap: CGFloat { bodySize * 0.85 }
    var quoteInnerSpacing: CGFloat { blockSpacing * 0.6 }

    // ── Code ────────────────────────────────────────────────────────────────

    var codePadding: CGFloat { 14 }
    var codeCornerRadius: CGFloat { 8 }

    // ── Rules, images, captions ───────────────────────────────────────────────

    var ruleSpacing: CGFloat { blockSpacing * 0.5 }
    var imageCornerRadius: CGFloat { 6 }
    var captionGap: CGFloat { bodySize * 0.4 }
    var captionSize: CGFloat { bodySize * 0.85 }
    var captionFont: Font { .system(size: captionSize, design: design) }

    // ── Article chrome (header title, metadata, rating) ───────────────────────
    // The reader's non-body pieces — the header title, the metadata line, and the
    // end-of-article rating — are sized from the body so they rescale with it
    // (Small … Giant) instead of holding a fixed size while the copy grows.

    /// The header title is the reading's sole h1 — the top of the heading scale —
    /// so it borrows the level-1 heading tokens (and, like the body, follows the
    /// chosen reader font).
    var titleFont: Font { headingFont(1) }
    var titleTracking: CGFloat { headingTracking(1) }

    /// The metadata line (site · author · reading time · tags) and the rating
    /// prompt: a muted, secondary size that follows the reader font, sized from
    /// the body.
    var metadataFont: Font { .system(size: bodySize * 0.85, design: design) }

    /// Star glyphs in the end-of-article rating control.
    var ratingStarFont: Font { .system(size: bodySize * 1.2, design: design) }
}
