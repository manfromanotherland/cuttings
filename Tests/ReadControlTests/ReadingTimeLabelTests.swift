// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `readingTimeLabel` turns a word count into a short "N min read" / "N hr read"
/// string at 200 wpm. These tests pin the boundaries: the missing-count and
/// one-minute-floor edges, and the minute/hour/hour-plus-minutes formatting.
final class ReadingTimeLabelTests: XCTestCase {
    private func label(wordCount: UInt32?) -> String? {
        makeReadingRow(wordCount: wordCount).readingTimeLabel
    }

    func testMissingOrZeroWordCountHasNoLabel() {
        XCTAssertNil(label(wordCount: nil))
        XCTAssertNil(label(wordCount: 0))
    }

    /// Any non-empty article rounds up to at least one minute (1 word ≈ 0 min).
    func testRoundsUpToAOneMinuteFloor() {
        XCTAssertEqual(label(wordCount: 1), "1 min read")
    }

    func testTypicalArticleReadsInMinutes() {
        XCTAssertEqual(label(wordCount: 1000), "5 min read")
    }

    /// 59 min stays in minutes; 60 rolls to a whole hour with no trailing minutes.
    func testMinutesJustUnderAnHour() {
        XCTAssertEqual(label(wordCount: 11800), "59 min read")
    }

    func testExactHourOmitsMinutes() {
        XCTAssertEqual(label(wordCount: 12000), "1 hr read")
    }

    func testHoursAndMinutesTogether() {
        XCTAssertEqual(label(wordCount: 16000), "1 hr 20 min read")
    }
}
