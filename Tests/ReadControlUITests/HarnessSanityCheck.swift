// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The harness proving itself: launch against a fresh, empty temp library,
/// confirm the app came up, then let `UITestCase.tearDown` terminate it, destroy
/// the temp library, and restore the dev's real defaults. The full bring-up smoke
/// test runs against a seeded corpus (see `SmokeTest`).
final class HarnessSanityCheck: UITestCase {
    func testLaunchesEmptyLibraryAndTearsDown() throws {
        let app = try launchApp()

        // Main view is up: the "All" smart-view row exists in the sidebar.
        XCTAssertTrue(app.byId(A11y.Sidebar.viewRow("all")).exists)

        // An empty library shows the "Nothing here yet" empty state, not a table.
        XCTAssertTrue(app.byId(A11y.List.emptyState).waitExists())
    }

    func testLaunchesOnboardingWhenNoLibrary() throws {
        let app = try launchOnboarding()
        XCTAssertTrue(app.byId(A11y.Onboarding.chooseLibrary).exists)
    }
}
