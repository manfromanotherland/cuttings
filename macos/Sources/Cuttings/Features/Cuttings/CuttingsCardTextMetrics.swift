// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Native text measurements for the fixed card frames supplied to
/// LazyLayoutKit. Measurements are cached at the active column width and never
/// read assets or construct offscreen card views.
@MainActor
final class CuttingsCardTextMetrics {
    static let articleTitleFont: NSFont = {
        let preferred = NSFont.preferredFont(forTextStyle: .headline)
        return NSFont.systemFont(ofSize: preferred.pointSize, weight: .semibold)
    }()

    static let quoteFont: NSFont = {
        let font = NSFont.preferredFont(forTextStyle: .title2)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }()

    static let sourceFont = NSFont.preferredFont(forTextStyle: .caption2)
    static let articleFooterPadding: CGFloat = 16
    static let articleFooterSpacing: CGFloat = 8
    static let articleFooterSourceLineHeight = max(14, sourceLineHeight)

    private struct ArticleTitleKey: Hashable {
        let text: String
        let halfPointWidth: Int
    }

    private struct QuoteKey: Hashable {
        let text: String
        let halfPointWidth: Int
    }

    private var articleFooterHeights: [ArticleTitleKey: CGFloat] = [:]
    private var quoteHeights: [QuoteKey: CGFloat] = [:]

    func articleFooterHeight(for title: String, width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - Self.articleFooterPadding * 2)
        let halfPointWidth = Int((textWidth * 2).rounded())
        let key = ArticleTitleKey(text: title, halfPointWidth: halfPointWidth)
        if let cached = articleFooterHeights[key] {
            return cached
        }

        let measured = Self.measuredArticleTitleHeight(
            title,
            width: CGFloat(halfPointWidth) / 2
        )
        let height = Self.articleFooterPadding * 2
            + measured
            + Self.articleFooterSpacing
            + Self.articleFooterSourceLineHeight
        articleFooterHeights[key] = height
        return height
    }

    func quoteCardHeight(for text: String, width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - Self.horizontalPadding)
        let halfPointWidth = Int((textWidth * 2).rounded())
        let key = QuoteKey(text: text, halfPointWidth: halfPointWidth)
        if let cached = quoteHeights[key] {
            return cached
        }

        let measured = Self.measuredQuoteHeight(
            text,
            width: CGFloat(halfPointWidth) / 2
        )
        let height = Self.verticalPadding
            + Self.quoteMarkHeight
            + Self.stackSpacing
            + measured
            + Self.sourceLineHeight
        quoteHeights[key] = height
        return height
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
        let maximumHeight = CGFloat(quoteLineLimit) * quoteLineHeight
            + CGFloat(quoteLineLimit - 1) * quoteLineSpacing
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

    private static let horizontalPadding: CGFloat = 44
    private static let verticalPadding: CGFloat = 44
    private static let quoteMarkHeight: CGFloat = 24
    private static let stackSpacing: CGFloat = 36
    private static let quoteLineSpacing: CGFloat = 4
    private static let quoteLineLimit = 12
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
