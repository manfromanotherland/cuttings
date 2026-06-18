// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Derives all fonts, sizes, and spacing for the native Markdown reader from the
/// user's typography settings. Mirrors the values the old WebView CSS used
/// (line-height 1.75, 680px content width, scaled headings, 0.9em code).
struct MarkdownTheme {
    let font: ReaderFont
    let fontSize: ReaderFontSize

    var design: Font.Design { font.design }
    var bodySize: CGFloat { fontSize.points }

    /// SwiftUI `lineSpacing` is the gap *between* lines, added on top of the
    /// natural (~1.2×) line height. (1.75 − 1.2) ≈ 0.55 approximates the old
    /// `line-height: 1.75`.
    var lineSpacing: CGFloat { bodySize * 0.55 }

    /// Vertical gap between top-level blocks (~1em).
    var blockSpacing: CGFloat { bodySize }

    var contentMaxWidth: CGFloat { 680 }

    var bodyFont: Font { .system(size: bodySize, design: design) }
    var codeFont: Font { .system(size: bodySize * 0.9, design: .monospaced) }

    func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: bodySize * 1.6
        case 2: bodySize * 1.3
        case 3: bodySize * 1.1
        default: bodySize
        }
    }

    func headingFont(_ level: Int) -> Font {
        .system(size: headingSize(level), design: design).weight(.bold)
    }
}
