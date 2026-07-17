// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Making it mine (and it sticks). Set a theme, reader typography, and a
/// list sort, confirm each applies live, then quit and relaunch against the same
/// library and confirm all of it was preserved.
///
/// No defaults are pinned: the whole point is that the app persists and reads
/// back its own writes, so a pin (which the NSArgumentDomain reads ahead of the
/// stored value) would mask the very persistence under test. `UITestCase`
/// snapshots and restores these keys, so the dev's real preferences are untouched.
///
/// Everything is verified through the UI, never the `defaults` CLI — a separate
/// process can't reliably read the app's live prefs (the same reason
/// `waitForFontValue` reads the control): theme via the selected-trait on the
/// theme button, font via the picker value, size via the slider position, and
/// sort via the row order.
final class PersonalizationJourney: UITestCase {
    private static let wordCountDesc = Fixtures.Oracle.Sort.wordCountDescending
    /// "Huge" is index 4 of [small, medium, large, xlarge, huge, giant] → 4/5 on the 0…1
    /// slider.
    private static let hugeSliderPosition = 4.0 / 5.0

    func testPreferencesApplyLiveAndPersist() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        sidebar.select(.all)
        XCTAssertTrue(list.waitForRowCount(Fixtures.Oracle.ViewCounts.all), "All lists 8")

        // 3. Change the list sort (Time to read, descending) → it reorders live to
        //    word-count descending (NULLs last: idx4 has no word_count).
        list.selectSortField(ReadingListPage.Sort.timeToRead)
        list.selectSortDirection(ReadingListPage.Sort.longestFirst)
        XCTAssertTrue(wait { list.orderedRowIds == Self.wordCountDesc }, "list reorders by time-to-read desc")

        // 1+2. Theme Dark, reader font Serif, size Huge — applied in one popover
        //      session, then verified live while the popover is still open.
        sidebar.setAppearance(theme: "dark", font: "Serif", sizePosition: Self.hugeSliderPosition)
        assertAppearanceApplied(context: "live")
        sidebar.dismissAppearancePopover()

        // 4. Quit and relaunch against the same library → every choice preserved.
        relaunchApp()
        sidebar.select(.all)
        XCTAssertTrue(list.waitForRowCount(Fixtures.Oracle.ViewCounts.all), "All lists 8 after relaunch")

        // Sort preserved — the row order is directly observable.
        XCTAssertTrue(wait { list.orderedRowIds == Self.wordCountDesc }, "sort preserved across relaunch")

        // Theme + typography preserved — reopen the popover and read them back.
        sidebar.openAppearancePopover()
        assertAppearanceApplied(context: "after relaunch")
        sidebar.dismissAppearancePopover()
    }

    /// Asserts the appearance popover reflects Dark / Serif / Huge. Assumes the
    /// popover is open.
    private func assertAppearanceApplied(context: String) {
        XCTAssertTrue(wait { sidebar.themeSelected("dark") }, "Dark theme (\(context))")
        XCTAssertTrue(sidebar.waitForFontValue("Serif"), "Serif font (\(context))")
        XCTAssertTrue(
            wait { abs(sidebar.fontSizePosition - Self.hugeSliderPosition) < 0.1 },
            "Huge size (\(context))"
        )
    }
}
