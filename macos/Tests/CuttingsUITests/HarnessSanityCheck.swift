// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The harness proving itself: launch against a fresh, empty temp library,
/// confirm the app came up, then let `UITestCase.tearDown` terminate it, destroy
/// the temp library, and restore the dev's real defaults. The full bring-up smoke
/// test runs against a seeded corpus (see `SmokeTest`).
final class HarnessSanityCheck: UITestCase {
    func testLaunchesEmptyLibraryAndTearsDown() throws {
        let app = try launchApp()

        // The board and its toolbar are mounted without relying on a sidebar.
        XCTAssertTrue(app.byId(A11y.List.rows).exists)
        XCTAssertTrue(app.byId(A11y.Filter.favorites).exists)

        // An empty library shows the "Nothing here yet" empty state, not a table.
        XCTAssertTrue(app.byId(A11y.List.emptyState).waitExists())
    }

    func testLaunchesOnboardingWhenNoLibrary() throws {
        let app = try launchOnboarding()
        XCTAssertTrue(app.byId(A11y.Onboarding.chooseLibrary).exists)
    }
}
