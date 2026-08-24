// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// First run: onboarding → choose an empty folder → the app scaffolds the
/// library, seeds the Welcome card, and opens it from the visual board.
final class FirstRunJourney: UITestCase {
    /// `SHA256("cuttings://welcome")`, matching `WelcomeArticle`.
    private let welcomeId = "32726b7601c556c1267735e6636be21606009f38d3d96ac0d46acf350a23bc5e"

    func testOnboardThenOpenWelcome() throws {
        try launchOnboarding()
        XCTAssertTrue(onboarding.isVisible, "Onboarding CTA should be shown")
        XCTAssertFalse(app.byId(A11y.List.rows).exists, "No board before a library is chosen")

        onboarding.chooseLibrary()
        XCTAssertTrue(onboarding.extensionContinueButton.waitExists(), "Extension step should follow the pick")
        onboarding.continuePastExtensionStep()

        XCTAssertTrue(app.byId(A11y.List.rows).waitExists(), "Board should appear")
        XCTAssertTrue(list.waitForRowCount(1), "Welcome is the only seeded card")
        XCTAssertTrue(list.row(welcomeId).waitExists(), "Welcome card should appear")

        list.open(welcomeId)
        XCTAssertEqual(reader.titleText, "Welcome to Cuttings")
        XCTAssertTrue(
            reader.bodyContains("articles, images, videos, and quotes that inspire you"),
            "Reader should render the welcome body as text"
        )
    }
}
