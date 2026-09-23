// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

final class CardThemePaletteTests: XCTestCase {
    func testParsesSixDigitSRGBHexDefensively() throws {
        let palette = try XCTUnwrap(CardThemePalette(themeColor: "  #1A80ff\n"))

        XCTAssertEqual(palette.background.red, 0x1A as Double / 255, accuracy: 0.000_001)
        XCTAssertEqual(palette.background.green, 0x80 as Double / 255, accuracy: 0.000_001)
        XCTAssertEqual(palette.background.blue, 1, accuracy: 0.000_001)
    }

    func testInvalidThemeColoursFallBackToTheSemanticCardTheme() {
        for value in [nil, "", "fff", "#fff", "#12345678", "#12xx56"] as [String?] {
            XCTAssertNil(CardThemePalette(themeColor: value), "Unexpectedly parsed \(value ?? "nil")")
        }
    }

    func testForegroundChoosesTheHigherContrastPureColour() throws {
        XCTAssertEqual(
            try XCTUnwrap(CardThemePalette(themeColor: "#000000")).foreground,
            .white
        )
        XCTAssertEqual(
            try XCTUnwrap(CardThemePalette(themeColor: "#ffffff")).foreground,
            .black
        )
        XCTAssertEqual(
            try XCTUnwrap(CardThemePalette(themeColor: "#757575")).foreground,
            .white
        )
        XCTAssertEqual(
            try XCTUnwrap(CardThemePalette(themeColor: "#767676")).foreground,
            .black
        )
    }

    func testWebsiteThemeOnlyAppliesToArticleCards() {
        var row = makeReadingRow()
        row.themeColor = "#123456"
        XCTAssertNotNil(OiaTheme.articlePalette(for: row))

        row.kind = .image
        XCTAssertNil(OiaTheme.articlePalette(for: row))
    }

    func testSocialPostKeepsTheNeutralNativeSurface() throws {
        let profile = try XCTUnwrap(ReadingSourceProfile.decode("""
        {"version":1,"source_type":"social_post","provider":"x",\
        "source_id":"123","author_handle":"example","attachments":[]}
        """))
        var row = makeReadingRow(sourceProfile: profile)
        row.themeColor = "#123456"

        XCTAssertTrue(row.isSocialPost)
        XCTAssertNil(OiaTheme.articlePalette(for: row))
    }

    func testImagePreviewUsesItsExactDominantColor() throws {
        let dominant = ReadingColor(red: 0.12, green: 0.34, blue: 0.56, weight: 0.72)
        let row = makeReadingRow(kind: .image, dominantColor: dominant)

        let color = try XCTUnwrap(OiaTheme.previewBackgroundColor(for: row))
        XCTAssertEqual(color.red, dominant.red)
        XCTAssertEqual(color.green, dominant.green)
        XCTAssertEqual(color.blue, dominant.blue)
    }

    func testExactDominantColorTakesPrecedenceOverArticleThemeColor() throws {
        let dominant = ReadingColor(red: 0.12, green: 0.34, blue: 0.56, weight: 0.72)
        var article = makeReadingRow(kind: .article, dominantColor: dominant)
        article.themeColor = "#abcdef"

        let color = try XCTUnwrap(OiaTheme.previewBackgroundColor(for: article))
        XCTAssertEqual(color.red, dominant.red)
        XCTAssertEqual(color.green, dominant.green)
        XCTAssertEqual(color.blue, dominant.blue)
    }

    func testPreviewWithoutAnalysisKeepsTheExistingFallback() throws {
        let image = makeReadingRow(kind: .image)
        XCTAssertNil(OiaTheme.previewBackgroundColor(for: image))

        var article = makeReadingRow()
        article.themeColor = "#123456"
        XCTAssertEqual(
            try XCTUnwrap(OiaTheme.previewBackgroundColor(for: article)),
            CardSRGBColor(hex: "#123456")
        )
    }

    func testChosenForegroundMeetsTextContrastAcrossSRGBSamples() {
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 17) {
                for blue in stride(from: 0, through: 255, by: 17) {
                    let hex = String(format: "#%02x%02x%02x", red, green, blue)
                    guard let palette = CardThemePalette(themeColor: hex) else {
                        return XCTFail("Could not parse generated colour \(hex)")
                    }
                    XCTAssertGreaterThanOrEqual(
                        palette.textContrast,
                        CardThemePalette.minimumTextContrast,
                        "\(hex) chose the wrong foreground"
                    )
                }
            }
        }
    }
}
