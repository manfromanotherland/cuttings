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
        XCTAssertNotNil(CuttingsTheme.articlePalette(for: row))

        row.kind = .image
        XCTAssertNil(CuttingsTheme.articlePalette(for: row))
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
