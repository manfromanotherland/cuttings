// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Organizing a messy library with tags. Open an article and the tag picker
/// (#), create-and-apply a brand-new tag, apply that (now existing) tag to a
/// second article, filter the list by its sidebar tile, then remove the tag from
/// each filtered article until the view empties into the "Clear tag filter"
/// state — asserting the chips, the live sidebar tile/count, tag filtering, and
/// on-disk frontmatter at every beat.
///
/// The whole walk revolves around one fresh tag, `important`, applied to two
/// untagged-or-lightly-tagged articles so its membership (and thus the filtered
/// list) is fully controlled:
///   `minimal` (idx4, no tags) and `unicode` (idx3, tag "unicode").
/// Pinning the sort keeps the filtered order deterministic (saved-at desc →
/// minimal(4) before unicode(3)).
final class TagOrganizingJourney: UITestCase {
    /// Deliberately avoids the letter "c": `typeText` drops a bare "c" on the test
    /// Mac, so a name containing it is mistyped ("focus" → "fous").
    private static let newTag = "important"

    // One end-to-end tag-organizing walk; asserting every beat keeps it long.
    // swiftlint:disable:next function_body_length
    func testCreateApplyFilterAndRemoveTags() throws {
        try launchApp(articles: Fixtures.standardCorpus) { options in
            options.pinnedDefaults["sortField"] = "savedAt"
            options.pinnedDefaults["sortAscending"] = "0"
        }
        let tag = Self.newTag

        // 1. Open an untagged article and the tag picker (#). The sheet lists the
        //    library's existing tags with a search field.
        list.open(Fixtures.Ids.minimal)
        XCTAssertEqual(reader.titleText, "Minimal")
        reader.openTagPicker()
        XCTAssertTrue(tagPicker.isVisible, "tag picker opened with its search field")
        XCTAssertTrue(tagPicker.row("programming").waitExists(), "existing tags listed in the picker")

        // 2. Type a brand-new tag name and create-and-apply it: a chip appears on
        //    the article, a new sidebar tile shows count 1, and the file records it.
        tagPicker.createAndApply(tag)
        tagPicker.done()
        XCTAssertTrue(reader.waitForTag(tag), "#\(tag) chip appears on the article")
        XCTAssertTrue(sidebar.waitForTagCount(tag, equals: 1), "new sidebar tile #\(tag) (1)")
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.minimal) { $0.tags.contains(tag) },
            "tag written to minimal's frontmatter"
        )

        // 3. Open a second article and apply the now-existing tag from the picker:
        //    its sidebar count increments 1→2, and it lands in that file too.
        list.open(Fixtures.Ids.unicode)
        XCTAssertEqual(reader.titleText, "Café Über 日本語 🎉")
        reader.openTagPicker()
        XCTAssertTrue(tagPicker.row(tag).waitExists(), "the created tag is now an existing picker row")
        // The picker floats the article's own tags to the top: `unicode` is a
        // least-used tag (count 1) yet sorts above more-used tags like
        // `programming` (count 3) purely because it's already applied here.
        XCTAssertEqual(
            tagPicker.orderedRowTags.first, "unicode",
            "the article's applied tag sorts to the top of the picker"
        )
        tagPicker.toggle(tag)
        tagPicker.done()
        XCTAssertTrue(reader.waitForTag(tag), "#\(tag) chip appears on the second article")
        XCTAssertTrue(sidebar.waitForTagCount(tag, equals: 2), "sidebar #\(tag) count 1→2")
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.unicode) { $0.tags.contains(tag) },
            "tag written to unicode's frontmatter"
        )

        // 4. Click the tag tile in the sidebar: the list filters to exactly the two
        //    articles carrying it (saved-at desc → minimal, then unicode).
        sidebar.selectTag(tag)
        XCTAssertTrue(list.waitForRowCount(2), "filtered to the two #\(tag) articles")
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitExists(), "minimal in the filter")
        XCTAssertTrue(list.row(Fixtures.Ids.unicode).waitExists(), "unicode in the filter")

        // 5. On a filtered article, remove the tag via the picker toggle: it leaves
        //    the filtered list and the sidebar count decrements 2→1.
        list.open(Fixtures.Ids.minimal)
        reader.openTagPicker()
        tagPicker.toggle(tag)
        tagPicker.done()
        XCTAssertTrue(reader.waitForNoTag(tag), "#\(tag) chip removed from minimal")
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitDisappears(), "minimal leaves the #\(tag) filter")
        XCTAssertTrue(sidebar.waitForTagCount(tag, equals: 1), "sidebar #\(tag) count 2→1")
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.minimal) { !$0.tags.contains(tag) },
            "tag removed from minimal's frontmatter"
        )

        // 5b. Remove it from the last filtered article too: the view empties into the
        //     "Clear tag filter" state and the now-empty tile drops from the sidebar.
        list.open(Fixtures.Ids.unicode)
        reader.openTagPicker()
        tagPicker.toggle(tag)
        tagPicker.done()
        XCTAssertTrue(list.row(Fixtures.Ids.unicode).waitDisappears(), "unicode leaves the #\(tag) filter")
        XCTAssertTrue(list.tagEmptyState.waitExists(), "empty filtered view shows the tag empty state")
        XCTAssertTrue(list.clearTagFilterButton.waitExists(), "Clear tag filter action offered")
        XCTAssertTrue(sidebar.waitForTagCount(tag, equals: 0), "empty #\(tag) tile drops from the sidebar")
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.unicode) { !$0.tags.contains(tag) },
            "tag removed from unicode's frontmatter"
        )
        // The unicode article keeps its original tag — only the new tag was removed.
        XCTAssertTrue(
            waitForFrontmatter(id: Fixtures.Ids.unicode) { $0.tags.contains("unicode") },
            "unicode's own tag is untouched"
        )

        // 6. Clear the tag filter → back to the All view with every article restored.
        list.clearTagFilter()
        XCTAssertTrue(list.waitForRowCount(Fixtures.Oracle.ViewCounts.all), "back to All (8 rows)")
        XCTAssertTrue(list.row(Fixtures.Ids.minimal).waitExists(), "minimal visible again in All")
    }
}
