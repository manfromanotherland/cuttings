// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The first-run onboarding screen.
struct OnboardingPage {
    let app: XCUIApplication

    var chooseLibraryButton: XCUIElement {
        app.byId(A11y.Onboarding.chooseLibrary)
    }

    var title: XCUIElement {
        app.byId(A11y.Onboarding.title)
    }

    var isVisible: Bool {
        chooseLibraryButton.exists
    }

    /// Click "Choose Library…". Under `--ui-testing` this scaffolds the pinned
    /// temp folder instead of opening an `NSOpenPanel`.
    func chooseLibrary() {
        chooseLibraryButton.clickWhenReady()
    }

    // ── Extension step (onboarding step 2) ────────────────────────────────────

    /// The "Continue" button on the extension-install step that follows the folder
    /// pick.
    var extensionContinueButton: XCUIElement {
        app.byId(A11y.Onboarding.extensionContinue)
    }

    /// Dismiss the extension-install step to reach the main view. (The download
    /// itself opens an `NSSavePanel`, which XCUITest can't drive, so the journey
    /// just clicks through.)
    func continuePastExtensionStep() {
        extensionContinueButton.clickWhenReady()
    }
}
