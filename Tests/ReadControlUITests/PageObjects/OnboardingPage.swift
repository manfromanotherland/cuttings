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
}
