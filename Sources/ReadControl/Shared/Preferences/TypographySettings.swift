// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum ReaderFont: String, CaseIterable, Identifiable {
    case system, serif, mono
    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .mono: "Monospace"
        }
    }

    /// SwiftUI font design used by the native reader.
    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}

enum ReaderFontSize: Int, CaseIterable, Identifiable {
    case small = 15, medium = 17, large = 19, xlarge = 21, huge = 23, giant = 25
    var id: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .xlarge: "Extra Large"
        case .huge: "Huge"
        case .giant: "Giant"
        }
    }

    /// Base body point size for the native reader.
    var points: CGFloat {
        CGFloat(rawValue)
    }
}

/// How wide the reader lays the article out — the *measure*, in points.
///
/// Medium (680) is the long-standing default and sits at the ~60–75 character
/// sweet spot for body text; the neighbours trade measure for either a tighter
/// column on a large display or fuller use of a small one. Values are fixed
/// points rather than a multiple of the body size, so widening the text does not
/// silently widen the column too.
enum ReaderWidth: Int, CaseIterable, Identifiable {
    case xsmall = 520, small = 600, medium = 680, large = 800, xlarge = 960
    var id: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .xsmall: "Extra Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .xlarge: "Extra Large"
        }
    }

    /// Maximum content width for the reader column.
    var points: CGFloat {
        CGFloat(rawValue)
    }

    /// Icons flanking the width slider in the sidebar's appearance popover —
    /// horizontal compress / expand, mirroring the small-to-large "Aa" pair on
    /// the font-size slider above it. Five graded column icons don't exist in SF
    /// Symbols, so the scale is conveyed by the slider and its two end caps.
    static let narrowIcon = "arrow.right.and.line.vertical.and.arrow.left"
    static let wideIcon = "arrow.left.and.line.vertical.and.arrow.right"
}

/// Leading between body lines, as a CSS-style line-height multiple of the body
/// size, in five even quarter-step stops from 1.25 to 2.25. Normal (1.75) is the
/// long-standing default and the middle stop.
///
/// The raw values are names, not numbers, so a stop can be retuned later without
/// resetting the choice every user has already saved — unlike `ReaderWidth`,
/// whose raw value *is* its measure.
enum ReaderLineHeight: String, CaseIterable, Identifiable {
    case tight, snug, normal, relaxed, loose
    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .tight: "Tight"
        case .snug: "Snug"
        case .normal: "Normal"
        case .relaxed: "Relaxed"
        case .loose: "Loose"
        }
    }

    /// Total line height as a multiple of the body point size.
    var multiple: CGFloat {
        switch self {
        case .tight: 1.25
        case .snug: 1.50
        case .normal: 1.75
        case .relaxed: 2.00
        case .loose: 2.25
        }
    }

    /// What to add *between* lines to reach `multiple`. Both SwiftUI's
    /// `lineSpacing` and AppKit's `NSParagraphStyle.lineSpacing` are gaps layered
    /// on top of the font's natural (~1.2×) line height, so the extra leading is
    /// the difference — never negative, so Tight can't overlap lines.
    var extraLeadingMultiple: CGFloat {
        max(multiple - 1.2, 0)
    }

    /// Icons capping the line-height slider in the sidebar's appearance popover —
    /// vertical compress / expand, the axis line height moves on. Same reasoning
    /// as `ReaderWidth`'s end caps: five graded glyphs don't exist, so the slider
    /// carries the scale.
    static let tightIcon = "arrow.down.and.line.horizontal.and.arrow.up"
    static let looseIcon = "arrow.up.and.line.horizontal.and.arrow.down"
}
