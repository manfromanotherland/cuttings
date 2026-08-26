// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

@MainActor
final class CuttingsCardTextMetricsTests: XCTestCase {
    func testScreenshotQuotesDoNotReserveCharacterBucketWhitespace() {
        let metrics = CuttingsCardTextMetrics()
        let short = "doubt is not a pleasant condition, but certainty is absurd"
        let long = [
            "A solar eclipse occurs when the Moon passes between Earth and the Sun, ",
            "thereby obscuring the view of the Sun from a small part of Earth, ",
            "totally or partially."
        ].joined()

        let shortHeight = metrics.quoteCardHeight(for: short, width: 403)
        let longHeight = metrics.quoteCardHeight(for: long, width: 403)

        XCTAssertLessThan(shortHeight, legacyQuoteHeight(for: short, width: 403))
        XCTAssertLessThan(longHeight, legacyQuoteHeight(for: long, width: 403))
        XCTAssertGreaterThan(longHeight, shortHeight)
    }

    func testQuoteHeightUsesRenderedWidthAndHardLineBreaks() {
        let metrics = CuttingsCardTextMetrics()
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
        let metrics = CuttingsCardTextMetrics()
        let long = String(repeating: "visible words ", count: 1000)
        let longer = String(repeating: "visible words ", count: 2000)

        XCTAssertEqual(
            metrics.quoteCardHeight(for: long, width: 220),
            metrics.quoteCardHeight(for: longer, width: 220)
        )
    }

    private func legacyQuoteHeight(for text: String, width: CGFloat) -> CGFloat {
        let charactersPerLine = max(12, Int(width / 11))
        let lines = min(
            12,
            max(1, Int(ceil(Double(text.count) / Double(charactersPerLine))))
        )
        return 22 + 24 + 18 + CGFloat(lines * 30) + 18 + 16 + 22
    }
}
