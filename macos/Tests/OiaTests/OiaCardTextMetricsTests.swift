// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import XCTest

@MainActor
final class OiaCardTextMetricsTests: XCTestCase {
    func testQuoteTypographyUsesTheBundledLightFace() {
        XCTAssertEqual(OiaCardTextMetrics.quoteFont.fontName, "CormorantGaramond-Light")
        XCTAssertEqual(OiaCardTextMetrics.quoteMarkFont.fontName, "CormorantGaramond-Light")
    }

    func testWidthScopedCacheEvictsThePreviousWidth() {
        var cache = WidthScopedHeightCache<String>()
        var calculations = 0

        func height(at width: Int) -> CGFloat {
            cache.value(for: "same text", width: width) {
                calculations += 1
                return CGFloat(calculations)
            }
        }

        XCTAssertEqual(height(at: 440), 1)
        XCTAssertEqual(height(at: 440), 1)
        XCTAssertEqual(height(at: 806), 2)
        XCTAssertEqual(height(at: 440), 3)
    }

    func testArticleFooterHeightUsesRenderedTitleWidth() {
        let metrics = OiaCardTextMetrics()
        let title = "Swell Wall Catchall by Anna Dawson — Sculptural Organizer & Hanger"

        XCTAssertGreaterThan(
            metrics.articleFooterHeight(for: title, width: 220),
            metrics.articleFooterHeight(for: title, width: 403)
        )
    }

    func testArticleFooterHeightUsesHardLineBreaks() {
        let metrics = OiaCardTextMetrics()

        XCTAssertGreaterThan(
            metrics.articleFooterHeight(for: "one\ntwo\nthree", width: 403),
            metrics.articleFooterHeight(for: "one two three", width: 403)
        )
    }

    func testArticleFooterHeightStopsAtTheVisibleLineLimit() {
        let metrics = OiaCardTextMetrics()
        let long = String(repeating: "visible words ", count: 100)
        let longer = String(repeating: "visible words ", count: 200)

        XCTAssertEqual(
            metrics.articleFooterHeight(for: long, width: 220),
            metrics.articleFooterHeight(for: longer, width: 220)
        )
    }

    func testArticleFooterHeightMatchesTheRenderedStack() {
        let metrics = OiaCardTextMetrics()

        for title in [
            "Spoke: Last mile delivery software",
            "Swell Wall Catchall by Anna Dawson — Sculptural Organizer & Hanger",
            String(repeating: "A deliberately long title ", count: 20)
        ] {
            XCTAssertEqual(
                metrics.articleFooterHeight(for: title, width: 320),
                renderedArticleFooterHeight(for: title, width: 320),
                accuracy: 0.5
            )
        }
    }

    func testQuoteHeightMatchesTheRenderedStack() {
        let metrics = OiaCardTextMetrics()

        for text in [
            "doubt is not a pleasant condition, but certainty is absurd",
            [
                "A solar eclipse occurs when the Moon passes between Earth and the Sun, ",
                "thereby obscuring the view of the Sun from a small part of Earth, ",
                "totally or partially."
            ].joined(),
            String(repeating: "A deliberately long quote ", count: 100)
        ] {
            XCTAssertEqual(
                metrics.quoteCardHeight(for: text, width: 403),
                renderedQuoteHeight(for: text, width: 403),
                accuracy: 0.5,
                "Height mismatch for: \(text.prefix(32))"
            )
        }
    }

    func testQuoteHeightUsesRenderedWidthAndHardLineBreaks() {
        let metrics = OiaCardTextMetrics()
        let text = "Behind your image, below your words, above your thoughts, the silence of another world awaits."

        XCTAssertLessThanOrEqual(
            metrics.quoteCardHeight(for: text, width: 403),
            metrics.quoteCardHeight(for: text, width: 220)
        )
        XCTAssertGreaterThan(
            metrics.quoteCardHeight(for: "one\ntwo\nthree", width: 403),
            metrics.quoteCardHeight(for: "one two three", width: 403)
        )
    }

    func testQuoteHeightStopsAtTheVisibleLineLimit() {
        let metrics = OiaCardTextMetrics()
        let long = String(repeating: "visible words ", count: 1000)
        let longer = String(repeating: "visible words ", count: 2000)

        XCTAssertEqual(
            metrics.quoteCardHeight(for: long, width: 220),
            metrics.quoteCardHeight(for: longer, width: 220)
        )
    }

    private func renderedArticleFooterHeight(for title: String, width: CGFloat) -> CGFloat {
        let view = VStack(
            alignment: .leading,
            spacing: OiaCardTextMetrics.articleFooterSpacing
        ) {
            Text(title)
                .font(Font(OiaCardTextMetrics.articleTitleFont))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Color.clear
                .frame(height: OiaCardTextMetrics.articleFooterSourceLineHeight)
        }
        .padding(OiaCardTextMetrics.articleFooterPadding)
        .frame(width: width, alignment: .leading)

        return ceil(NSHostingView(rootView: view).fittingSize.height)
    }

    private func renderedQuoteHeight(for text: String, width: CGFloat) -> CGFloat {
        let view = VStack(alignment: .leading, spacing: 0) {
            renderedQuoteMark("“")
            Text(text)
                .font(Font(OiaCardTextMetrics.quoteFont))
                .lineSpacing(OiaCardTextMetrics.quoteLineSpacing)
                .lineLimit(OiaCardTextMetrics.quoteLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, OiaCardTextMetrics.quoteMarkSpacing)
            renderedQuoteMark("”")
                .padding(.top, OiaCardTextMetrics.quoteMarkSpacing)
        }
        .padding(.horizontal, OiaCardTextMetrics.quoteHorizontalPadding)
        .padding(.vertical, OiaCardTextMetrics.quoteVerticalPadding)
        .frame(width: width, alignment: .leading)

        return ceil(NSHostingView(rootView: view).fittingSize.height)
    }

    private func renderedQuoteMark(_ mark: String) -> some View {
        Text(mark)
            .font(Font(OiaCardTextMetrics.quoteMarkFont))
            .fixedSize()
            .offset(y: OiaCardTextMetrics.quoteMarkVerticalOffset)
            .frame(
                maxWidth: .infinity,
                minHeight: OiaCardTextMetrics.quoteMarkHeight,
                maxHeight: OiaCardTextMetrics.quoteMarkHeight,
                alignment: .leading
            )
    }
}
