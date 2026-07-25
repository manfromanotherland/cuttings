// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `TagRules.isWithinLength` mirrors readcontrol-core's `MAX_TAG_LEN` so the tag
/// picker can reject an over-long name inline. These tests pin the limit's value
/// and its inclusive boundary, and confirm the length is counted in Unicode
/// scalar values (matching the core) rather than UTF-8 bytes.
final class TagRulesTests: XCTestCase {
    func testLimitMatchesTheCore() {
        XCTAssertEqual(TagRules.maxLength, 20)
    }

    func testEmptyAndShortNamesFit() {
        XCTAssertTrue(TagRules.isWithinLength(""))
        XCTAssertTrue(TagRules.isWithinLength("rust"))
    }

    /// The boundary is inclusive: exactly maxLength fits, one past it does not.
    func testBoundaryIsInclusive() {
        let atLimit = String(repeating: "a", count: TagRules.maxLength)
        let overLimit = String(repeating: "a", count: TagRules.maxLength + 1)
        XCTAssertTrue(TagRules.isWithinLength(atLimit))
        XCTAssertFalse(TagRules.isWithinLength(overLimit))
    }

    /// "é" is one scalar but two UTF-8 bytes; 25 of them is 50 bytes yet still 25
    /// characters, so it must fit — the limit counts scalars, not bytes.
    func testCountsScalarsNotBytes() {
        let multibyte = String(repeating: "é", count: TagRules.maxLength)
        XCTAssertEqual(multibyte.utf8.count, TagRules.maxLength * 2)
        XCTAssertTrue(TagRules.isWithinLength(multibyte))
    }
}
