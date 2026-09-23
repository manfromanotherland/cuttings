// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreText

private final class OiaCardFontBundleToken: NSObject {}

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

    static let quoteFont = makeQuoteFont(ofSize: 24, opticalSize: 24)
    static let quoteMarkFont = makeQuoteFont(ofSize: 59, opticalSize: 6)

    static let socialPostFont = NSFont.preferredFont(forTextStyle: .body)
    static let sourceFont = NSFont.preferredFont(forTextStyle: .caption2)
    static let articleFooterPadding: CGFloat = 16
    static let articleFooterSpacing: CGFloat = 8
    static let articleFooterSourceLineHeight = max(14, sourceLineHeight)
    static let quoteHorizontalPadding: CGFloat = 34.5
    static let quoteVerticalPadding: CGFloat = 24
    static let quoteMinimumHeight: CGFloat = 300
    static let quoteMarkHeight: CGFloat = 15
    static let quoteMarkVerticalOffset: CGFloat = 21
    static let quoteMarkSpacing: CGFloat = 23
    static let quoteLineSpacing: CGFloat = 7
    static let quoteLineLimit = 12
    static let socialPostPadding: CGFloat = 16
    static let socialPostSpacing: CGFloat = 12
    static let socialPostHeaderHeight = max(
        34,
        ceil(
            NSFont.preferredFont(forTextStyle: .callout).ascender
                - NSFont.preferredFont(forTextStyle: .callout).descender
                + NSFont.preferredFont(forTextStyle: .callout).leading
        )
            + 1
            + ceil(
                NSFont.preferredFont(forTextStyle: .caption1).ascender
                    - NSFont.preferredFont(forTextStyle: .caption1).descender
                    + NSFont.preferredFont(forTextStyle: .caption1).leading
            )
    )
    static let socialPostLineSpacing: CGFloat = 3
    static let socialPostLineLimit = 10

    private var articleFooterHeights = WidthScopedHeightCache<String>()
    private var quoteHeights = WidthScopedHeightCache<String>()
    private var socialPostHeights = WidthScopedHeightCache<SocialPostHeightKey>()

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
        let textWidth = max(1, width - Self.quoteHorizontalPadding * 2)
        let halfPointWidth = Int((textWidth * 2).rounded())
        return quoteHeights.value(for: text, width: halfPointWidth) {
            let measured = Self.measuredQuoteHeight(
                text,
                width: CGFloat(halfPointWidth) / 2
            )
            let intrinsicHeight = Self.quoteVerticalPadding * 2
                + Self.quoteMarkHeight * 2
                + Self.quoteMarkSpacing * 2
                + measured
            return max(Self.quoteMinimumHeight, intrinsicHeight)
        }
    }

    func socialPostCardHeight(
        for text: String,
        width: CGFloat,
        attachmentAspectRatio: CGFloat?
    ) -> CGFloat {
        let contentWidth = max(1, width - Self.socialPostPadding * 2)
        let halfPointWidth = Int((contentWidth * 2).rounded())
        let key = SocialPostHeightKey(
            text: text,
            attachmentAspectRatio: attachmentAspectRatio
        )
        return socialPostHeights.value(for: key, width: halfPointWidth) {
            let measured = Self.measuredSocialPostHeight(
                text,
                width: CGFloat(halfPointWidth) / 2
            )
            let attachmentHeight = attachmentAspectRatio.map { ratio in
                contentWidth / max(0.01, ratio)
            } ?? 0
            let spacingCount: CGFloat = attachmentAspectRatio == nil ? 1 : 2
            return Self.socialPostPadding * 2
                + Self.socialPostHeaderHeight
                + Self.socialPostSpacing * spacingCount
                + measured
                + attachmentHeight
        }
    }

    private static func measuredQuoteHeight(_ text: String, width: CGFloat) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
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

    private static let newsreaderPostScriptName = "Newsreader16pt-Regular"
    private static let weightAxis = NSNumber(value: UInt32(0x7767_6874))
    private static let opticalSizeAxis = NSNumber(value: UInt32(0x6F70_737A))

    private static func makeQuoteFont(ofSize size: CGFloat, opticalSize: CGFloat) -> NSFont {
        guard let fontURL = Bundle(for: OiaCardFontBundleToken.self).url(
            forResource: "Newsreader-VariableFont_opsz-wght",
            withExtension: "ttf"
        ),
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL)
            as? [CTFontDescriptor],
            let baseDescriptor = descriptors.first(where: { descriptor in
                (CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String)
                    == newsreaderPostScriptName
            })
        else {
            assertionFailure("Bundled Newsreader variable font is missing")
            return NSFont.systemFont(ofSize: size, weight: .light)
        }

        let variations: [NSNumber: NSNumber] = [
            weightAxis: NSNumber(value: 300),
            opticalSizeAxis: NSNumber(value: Double(opticalSize))
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            baseDescriptor,
            [kCTFontVariationAttribute: variations] as CFDictionary
        )

        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
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

    private static func measuredSocialPostHeight(_ text: String, width: CGFloat) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = socialPostLineSpacing
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [
                .font: socialPostFont,
                .paragraphStyle: paragraphStyle
            ]
        )
        let maximumHeight = CGFloat(socialPostLineLimit) * socialPostLineHeight
            + CGFloat(socialPostLineLimit - 1) * socialPostLineSpacing
        return min(maximumHeight, max(socialPostLineHeight, ceil(bounds.height)))
    }

    private static let articleTitleLineLimit = 3
    private static let articleTitleLineHeight = ceil(
        articleTitleFont.ascender - articleTitleFont.descender + articleTitleFont.leading
    )
    private static let quoteLineHeight = floor(
        quoteFont.ascender - quoteFont.descender + quoteFont.leading
    )
    private static let sourceLineHeight = ceil(
        sourceFont.ascender - sourceFont.descender + sourceFont.leading
    )
    private static let socialPostLineHeight = ceil(
        socialPostFont.ascender - socialPostFont.descender + socialPostFont.leading
    )

    private struct SocialPostHeightKey: Hashable {
        let text: String
        let attachmentAspectRatio: CGFloat?
    }
}
