// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// First run: onboarding → choose an empty folder → the app scaffolds the
/// library and seeds the Welcome article → the main view appears with All 1 /
/// Unread 1, the Welcome article auto-selected and rendered → it carries a
/// pre-set 5-star rating → mark it read → Unread 0 (it stays in All).
final class FirstRunJourney: UITestCase {
    /// The Welcome article's content-addressed id, seeded by the app into a fresh
    /// library — `SHA256(normalize("https://www.readcontrol.app"))`, matching
    /// `WelcomeArticle`.
    private let welcomeId = "d9b68f436a63429191a157ea8ad8286bad858b867aaf18c540af99d22565d21f"

    func testOnboardThenReadWelcome() throws {
        // 1. Fresh launch with no library → the onboarding screen, and no
        //    three-pane UI yet.
        try launchOnboarding()
        XCTAssertTrue(onboarding.isVisible, "Onboarding CTA should be shown")
        XCTAssertFalse(app.byId(A11y.Sidebar.viewRow("all")).exists, "No sidebar before a library is chosen")
        XCTAssertFalse(app.byId(A11y.List.table).exists, "No reading list before a library is chosen")

        // 2. Choose the (empty) library folder → the app scaffolds it and seeds
        //    the Welcome article, then boots into the main view.
        onboarding.chooseLibrary()
        XCTAssertTrue(app.byId(A11y.Sidebar.viewRow("all")).waitExists(), "Main view should appear")

        // 3. Counts reflect the single seeded article.
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 1), "All should be 1")
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 1), "Unread should be 1")

        // 4. The Welcome article is auto-selected and rendered as native text.
        XCTAssertEqual(reader.titleText, "Welcome to ReadControl")
        XCTAssertTrue(
            reader.bodyContains("manage your readings"),
            "Reader should render the welcome body as text"
        )

        // 5. The seeded article ships with a pre-set 5-star rating on disk.
        XCTAssertTrue(
            waitForFrontmatter(id: welcomeId) { $0.rating == 5 },
            "The seeded Welcome article should have a 5-star rating"
        )

        // 6. Mark it read → Unread drops to 0, but it stays in All (read, not
        //    archived), and the file records the read state.
        reader.markReadToggle()
        XCTAssertTrue(sidebar.waitForCount(.unread, equals: 0), "Unread should drop to 0")
        XCTAssertTrue(sidebar.waitForCount(.all, equals: 1), "All should stay 1")
        XCTAssertTrue(
            waitForFrontmatter(id: welcomeId) { $0.isRead },
            "The article file should record read_at"
        )
    }
}
