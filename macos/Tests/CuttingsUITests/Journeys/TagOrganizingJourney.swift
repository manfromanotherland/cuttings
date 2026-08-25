// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Create a tag from the inspector, apply it to a second card, filter the board
/// from the toolbar, then remove it from both cards.
final class TagOrganizingJourney: UITestCase {
    private static let newTag = "important"

    // One end-to-end organizing walk; asserting each persistence boundary keeps it long.
    // swiftlint:disable:next function_body_length
    func testCreateApplyFilterAndRemoveTags() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        let tag = Self.newTag

        list.open(Fixtures.Ids.minimal)
        XCTAssertEqual(reader.titleText, "Minimal")
        reader.openTagPicker()
        XCTAssertTrue(tagPicker.isVisible, "tag picker opened")
        XCTAssertTrue(tagPicker.row("programming").waitExists(), "existing tags are listed")
        tagPicker.createAndApply(tag)
        tagPicker.done()
        XCTAssertTrue(reader.waitForTag(tag), "#\(tag) appears on the first card")
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.minimal) { $0.tags.contains(tag) },
            "tag written to minimal's frontmatter"
        )

        reader.close()
        list.open(Fixtures.Ids.unicode)
        reader.openTagPicker()
        XCTAssertTrue(tagPicker.row(tag).waitExists(), "created tag is available on another card")
        XCTAssertEqual(tagPicker.orderedRowTags.first, "unicode", "the card's applied tag stays first")
        tagPicker.toggle(tag)
        tagPicker.done()
        XCTAssertTrue(reader.waitForTag(tag), "#\(tag) appears on the second card")
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.unicode) { $0.tags.contains(tag) },
            "tag written to unicode's frontmatter"
        )

        reader.close()
        list.selectTagFilter(tag)
        XCTAssertTrue(list.waitForRowCount(2), "toolbar filter shows the two tagged cards")
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitExists(), "minimal matches the filter")
        XCTAssertTrue(list.row(Fixtures.Ids.unicode).waitExists(), "unicode matches the filter")

        list.open(Fixtures.Ids.minimal)
        reader.openTagPicker()
        tagPicker.toggle(tag)
        tagPicker.done()
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.minimal) { !$0.tags.contains(tag) },
            "tag removed from minimal's frontmatter"
        )
        reader.close()
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitDisappears(), "minimal leaves the tag filter")

        list.open(Fixtures.Ids.unicode)
        reader.openTagPicker()
        tagPicker.toggle(tag)
        tagPicker.done()
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.unicode) { !$0.tags.contains(tag) },
            "tag removed from unicode's frontmatter"
        )
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.unicode) { $0.tags.contains("unicode") },
            "the card's original tag is untouched"
        )
        reader.close()

        XCTAssertTrue(list.tagEmptyState.waitExists(), "empty tag filter state appears")
        XCTAssertTrue(list.clearTagFilterButton.waitExists(), "clear filter action is offered")
        list.clearTagFilter()
        XCTAssertTrue(list.waitForRowCount(Fixtures.standardCorpus.count), "full board returns")
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitExists(), "minimal is visible again")
    }
}
