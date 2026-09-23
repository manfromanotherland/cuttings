// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

struct WidthScopedHeightCache<Key: Hashable> {
    private var activeWidth: Int?
    private var values: [Key: CGFloat] = [:]

    mutating func value(
        for key: Key,
        width: Int,
        calculate: () -> CGFloat
    ) -> CGFloat {
        if activeWidth != width {
            activeWidth = width
            values.removeAll(keepingCapacity: true)
        }
        if let cached = values[key] {
            return cached
        }

        let value = calculate()
        values[key] = value
        return value
    }
}

/// Native text measurements for the fixed card frames supplied to
/// LazyLayoutKit. Measurements are cached at the active column width and never
/// read assets or construct offscreen card views.
@MainActor
final class OiaCardTextMetrics {
    static let articleTitleFont: NSFont = {
        let preferred = NSFont.preferredFont(forTextStyle: .headline)
        return NSFont.systemFont(ofSize: preferred.pointSize, weight: .semibold)
    }()

    static let quoteFont: NSFont = {
        let preferred = NSFont.preferredFont(forTextStyle: .title1)
        let descriptor = preferred.fontDescriptor.withDesign(.serif)
            ?? preferred.fontDescriptor
        return NSFont(descriptor: descriptor, size: preferred.pointSize)
            ?? preferred
    }()

    static let sourceFont = NSFont.preferredFont(forTextStyle: .caption2)
    static let articleFooterPadding: CGFloat = 16
    static let articleFooterSpacing: CGFloat = 8
    static let articleFooterSourceLineHeight = max(14, sourceLineHeight)
    static let quotePadding: CGFloat = 24
    static let quoteMarkSize: CGFloat = 28
    static let quoteMarkHeight: CGFloat = 28
    static let quoteMarkSpacing: CGFloat = 12
    static let quoteSourceSpacing: CGFloat = 16
    static let quoteSourceLineHeight = max(14, sourceLineHeight)
    static let quoteLineSpacing: CGFloat = 4
    static let quoteLineLimit = 12

    private var articleFooterHeights = WidthScopedHeightCache<String>()
    private var quoteHeights = WidthScopedHeightCache<String>()

    func articleFooterHeight(for title: String, width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - Self.articleFooterPadding * 2)
        let halfPointWidth = Int((textWidth * 2).rounded())
        return articleFooterHeights.value(for: title, width: halfPointWidth) {
            let measured = Self.measuredArticleTitleHeight(
                title,
                width: CGFloat(halfPointWidth) / 2
            )
            return Self.articleFooterPadding * 2
                + measured
                + Self.articleFooterSpacing
                + Self.articleFooterSourceLineHeight
        }
    }

    func quoteCardHeight(for text: String, width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - Self.quotePadding * 2)
        let halfPointWidth = Int((textWidth * 2).rounded())
        return quoteHeights.value(for: text, width: halfPointWidth) {
            let measured = Self.measuredQuoteHeight(
                text,
                width: CGFloat(halfPointWidth) / 2
            )
            return Self.quotePadding * 2
                + Self.quoteMarkHeight * 2
                + Self.quoteMarkSpacing * 2
                + measured
                + Self.quoteSourceSpacing
                + Self.quoteSourceLineHeight
        }
    }

    private static func measuredQuoteHeight(_ text: String, width: CGFloat) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = quoteLineSpacing
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [
                .font: quoteFont,
                .paragraphStyle: paragraphStyle
            ]
        )
        let firstLineHeight = quoteFont.ascender - quoteFont.descender
        let lineAdvance = firstLineHeight + quoteFont.leading + quoteLineSpacing
        let maximumHeight = ceil(
            firstLineHeight + CGFloat(quoteLineLimit - 1) * lineAdvance
        )
        return min(maximumHeight, max(quoteLineHeight, ceil(bounds.height)))
    }

    private static func measuredArticleTitleHeight(_ text: String, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [.font: articleTitleFont]
        )
        let maximumHeight = CGFloat(articleTitleLineLimit) * articleTitleLineHeight
        return min(maximumHeight, max(articleTitleLineHeight, ceil(bounds.height)))
    }

    private static let articleTitleLineLimit = 3
    private static let articleTitleLineHeight = ceil(
        articleTitleFont.ascender - articleTitleFont.descender + articleTitleFont.leading
    )
    private static let quoteLineHeight = ceil(
        quoteFont.ascender - quoteFont.descender + quoteFont.leading
    )
    private static let sourceLineHeight = ceil(
        sourceFont.ascender - sourceFont.descender + sourceFont.leading
    )
}
