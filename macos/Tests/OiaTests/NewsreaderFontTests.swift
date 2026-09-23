// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreText
import XCTest

@MainActor
final class NewsreaderFontTests: XCTestCase {
    private let weightAxis = NSNumber(value: UInt32(0x7767_6874))
    private let opticalSizeAxis = NSNumber(value: UInt32(0x6F70_737A))
    private let resourceName = "Newsreader-VariableFont_opsz-wght.ttf"

    func testQuoteTypographyUsesTheBundledNewsreaderLightVariations() throws {
        try assertBundledNewsreader(
            OiaCardTextMetrics.quoteFont,
            pointSize: 24,
            opticalSize: 24
        )
        try assertBundledNewsreader(
            OiaCardTextMetrics.quoteMarkFont,
            pointSize: 59,
            opticalSize: 6
        )
    }

    func testNewsreaderContainsDistinctCurlyQuoteGlyphs() {
        let font = OiaCardTextMetrics.quoteMarkFont as CTFont
        var characters: [UniChar] = [0x201C, 0x201D]
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)

        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count))
        XCTAssertNotEqual(glyphs[0], 0)
        XCTAssertNotEqual(glyphs[1], 0)
        XCTAssertNotEqual(glyphs[0], glyphs[1])
    }

    private func assertBundledNewsreader(
        _ font: NSFont,
        pointSize: CGFloat,
        opticalSize: Double
    ) throws {
        let bundledURL = try XCTUnwrap(
            Bundle(for: NewsreaderFontTests.self).url(
                forResource: "Newsreader-VariableFont_opsz-wght",
                withExtension: "ttf"
            )
        )

        XCTAssertEqual(font.familyName, "Newsreader")
        XCTAssertEqual(font.pointSize, pointSize)
        XCTAssertEqual(bundledURL.lastPathComponent, resourceName)
        XCTAssertEqual(fontURL(for: font)?.lastPathComponent, resourceName)
        XCTAssertEqual(variationValue(for: weightAxis, in: font), 300)
        XCTAssertEqual(variationValue(for: opticalSizeAxis, in: font), opticalSize)
    }

    private func variationValue(for axis: NSNumber, in font: NSFont) -> Double? {
        let variations = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
        return variations?[axis]?.doubleValue
    }

    private func fontURL(for font: NSFont) -> URL? {
        CTFontCopyAttribute(font as CTFont, kCTFontURLAttribute) as? URL
    }
}
