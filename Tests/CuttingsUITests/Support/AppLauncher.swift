// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// How to launch the app under test: which temp library / DB to redirect it at,
/// which onboarding folder to auto-pick, which defaults to pin for determinism,
/// and any extra environment or launch arguments. Consumed by `AppLauncher`.
struct LaunchOptions {
    /// Boots the app straight against this library (sets `CUTTINGS_TEST_LIBRARY`).
    var libraryPath: String?

    /// Redirects the index DB here (sets `CUTTINGS_TEST_DB`).
    var dbPath: String?

    /// Makes onboarding's "Choose Library…" pick this folder without an
    /// `NSOpenPanel` (sets `CUTTINGS_TEST_ONBOARDING_PICK`).
    var onboardingPickPath: String?

    /// Throwaway `UserDefaults` suite the app persists preferences to (sets
    /// `CUTTINGS_TEST_DEFAULTS`), so a test never touches the real defaults domain.
    var defaultsSuite: String?

    /// Defaults pinned through the NSArgumentDomain (`-key value` launch args),
    /// which `UserDefaults` reads ahead of the persisted store — so a run starts
    /// from a known theme/font/sort no matter what's on disk, without writing to
    /// (or having to restore) the real defaults. Values are formatted the way the
    /// argument domain expects: a raw string, or `"0"`/`"1"` for a Bool.
    var pinnedDefaults: [String: String] = [:]

    /// Extra environment variables merged into the launch environment.
    var environment: [String: String] = [:]

    /// Extra launch arguments appended after the standard ones.
    var arguments: [String] = []

    init(libraryPath: String? = nil, dbPath: String? = nil, onboardingPickPath: String? = nil) {
        self.libraryPath = libraryPath
        self.dbPath = dbPath
        self.onboardingPickPath = onboardingPickPath
    }
}

/// Configures and launches the real app as a separate process for XCUITest.
enum AppLauncher {
    /// Launches the app with `--ui-testing` plus the redirections in `options`,
    /// waits for a window to appear, and returns the running application. Callers
    /// (see `UITestCase`) then wait on the specific ready element — the main
    /// sidebar or the onboarding button — for the screen they expect.
    @discardableResult
    static func launch(_ options: LaunchOptions = LaunchOptions()) -> XCUIApplication {
        let app = XCUIApplication()

        var arguments = ["--ui-testing"]
        // Pin defaults via the argument domain: `-key value` pairs, read ahead of
        // the persisted store, keep the run deterministic without mutating the
        // real defaults.
        for (key, value) in options.pinnedDefaults {
            arguments += ["-\(key)", value]
        }
        arguments += options.arguments
        app.launchArguments = arguments

        var environment = options.environment
        if let libraryPath = options.libraryPath {
            environment["CUTTINGS_TEST_LIBRARY"] = libraryPath
        }
        if let dbPath = options.dbPath {
            environment["CUTTINGS_TEST_DB"] = dbPath
        }
        if let pick = options.onboardingPickPath {
            environment["CUTTINGS_TEST_ONBOARDING_PICK"] = pick
        }
        if let suite = options.defaultsSuite {
            environment["CUTTINGS_TEST_DEFAULTS"] = suite
        }
        app.launchEnvironment = environment

        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 20)
        return app
    }
}
