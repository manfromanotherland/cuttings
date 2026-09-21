// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Tuning the reading measure. Open an article, narrow the reader's **Width** and
/// open up its **Line Height** from Settings › Typography, confirm the body column
/// actually reflows to the new measure, then quit and relaunch and confirm both
/// choices came back.
///
/// Width is directly observable — the body's text runs fill the measure, so the
/// column's width is read off the rendered text views (`reader.bodyWidth`). Line
/// height is not measurable through XCUITest (leading lives inside the text
/// view's layout, not its frame), so it is verified the way `PersonalizationJourney`
/// verifies the font: by reading the control back, live and after a relaunch.
///
/// No defaults are pinned for the typography keys — the point is that the app
/// persists and reads back its own writes, and a pin would shadow the stored
/// value through the NSArgumentDomain. `UITestCase` gives the run its own
/// defaults suite, so the dev's real preferences are untouched.
final class ReaderLayoutJourney: UITestCase {
    func testReaderWidthAndLineHeightApplyLiveAndPersist() throws {
        try launchApp(articles: Fixtures.standardCorpus)

        // 1. Open the long article and let the default Medium measure settle.
        list.open(Fixtures.Ids.kitchenSink)
        XCTAssertEqual(reader.titleText, "The Complete Markdown Sample")
        XCTAssertTrue(
            reader.waitForBodyWidth(ReaderWidth.medium.points),
            "body starts at the Medium measure (\(ReaderWidth.medium.points) pt)"
        )

        // 2. Settings › Typography: narrow the column and open up the leading.
        XCTAssertTrue(settings.openTypography(), "Typography tab opened")
        settings.setWidth(ReaderWidth.xsmall.label)
        settings.setLineHeight(ReaderLineHeight.loose.label)
        assertTypographyApplied(context: "live")
        settings.close()

        // 3. The reader reflowed live to the narrower measure.
        XCTAssertTrue(
            reader.waitForBodyWidth(ReaderWidth.xsmall.points),
            "body reflowed to the Extra Small measure (\(ReaderWidth.xsmall.points) pt)"
        )
        XCTAssertEqual(reader.titleText, "The Complete Markdown Sample", "reader intact after reflow")

        // 4. Quit and relaunch against the same library → both choices preserved,
        //    in the controls and in the reader itself.
        relaunchApp()
        sidebar.select(.all)
        list.open(Fixtures.Ids.kitchenSink)
        XCTAssertTrue(
            reader.waitForBodyWidth(ReaderWidth.xsmall.points),
            "narrow measure preserved across relaunch"
        )

        XCTAssertTrue(settings.openTypography(), "Typography tab opened after relaunch")
        assertTypographyApplied(context: "after relaunch")
        settings.close()
    }

    /// The same two settings from the sidebar's appearance popover, which offers
    /// them as icon-capped sliders rather than named pickers. Both write the same
    /// preferences as Settings, so this checks the popover is wired to them and
    /// that the reader follows.
    func testWidthAndLineHeightFromTheSidebarPopover() throws {
        try launchApp(articles: Fixtures.standardCorpus)
        list.open(Fixtures.Ids.kitchenSink)
        XCTAssertTrue(reader.waitForBodyWidth(ReaderWidth.medium.points), "body starts at Medium")

        // Both sliders to their far end: Extra Large width, Loose line height —
        // each the last of five stops, so 1.0 normalized.
        sidebar.setWidth(position: 1.0)
        sidebar.setLineHeight(position: 1.0)
        XCTAssertTrue(
            wait { abs(sidebar.widthPosition - 1.0) < 0.1 },
            "width slider sits at the wide end"
        )
        XCTAssertTrue(
            wait { abs(sidebar.lineHeightPosition - 1.0) < 0.1 },
            "line height slider sits at the loose end"
        )
        sidebar.dismissAppearancePopover()

        XCTAssertTrue(
            reader.waitForBodyWidth(ReaderWidth.xlarge.points),
            "body widened to the Extra Large measure (\(ReaderWidth.xlarge.points) pt)"
        )
    }

    /// Asserts the Typography pickers read back Extra Small / Loose. Assumes the
    /// Typography tab is open. Segmented options carry the selected trait, which
    /// is the only way to read such a picker's value back.
    private func assertTypographyApplied(context: String) {
        XCTAssertTrue(
            wait { settings.widthSelected(ReaderWidth.xsmall.label) },
            "Width is Extra Small (\(context))"
        )
        XCTAssertTrue(
            wait { settings.lineHeightSelected(ReaderLineHeight.loose.label) },
            "Line Height is Loose (\(context))"
        )
    }
}
