// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Narrow test seams for the XCUITest end-to-end suite.
///
/// XCUITest launches the real app as a separate process; the only channels in
/// are launch arguments and environment variables. What these expose are
/// environment **redirections** — a temp library folder, a temp index DB, and a
/// scripted onboarding pick — plus a switch that turns off host-machine side
/// effects. They are *not* mocks: the real core and the real files on disk are
/// still exercised.
///
/// Every value-returning accessor yields `nil` unless the app was launched with
/// `--ui-testing`, so a normal launch reads no environment overrides and behaves
/// exactly as before — even if one of these variables happens to be set.
enum TestHooks {
    /// True when the app was launched by the UI-test harness (passes `--ui-testing`).
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    /// Library folder to boot against, replacing the persisted bookmark.
    static var libraryPath: String? {
        env("CUTTINGS_TEST_LIBRARY")
    }

    /// Index-DB path, kept out of the real `Application Support` directory.
    static var dbPath: String? {
        env("CUTTINGS_TEST_DB")
    }

    /// Folder the onboarding "Choose Library…" flow should pick directly,
    /// instead of showing an `NSOpenPanel` (which XCUITest can't drive).
    static var onboardingPickPath: String? {
        env("CUTTINGS_TEST_ONBOARDING_PICK")
    }

    /// Throwaway `UserDefaults` suite name for persisted preferences, so a test
    /// that changes theme, typography, or card size never touches the real defaults domain
    /// (see `AppDefaults`). `nil` in production. The harness destroys the suite.
    static var defaultsSuiteName: String? {
        env("CUTTINGS_TEST_DEFAULTS")
    }

    /// Artificially holds library hydration so UI tests can assert that the
    /// window shell and toolbar do not depend on indexing completing.
    static var libraryHydrationDelayNanoseconds: UInt64? {
        env("CUTTINGS_TEST_LIBRARY_HYDRATION_DELAY_MS")
            .flatMap(UInt64.init)
            .map { $0 * 1_000_000 }
    }

    /// Records a first-frame event for the command-line startup regression
    /// probe. The path is available only under `--ui-testing`.
    static func recordStartupEvent(_ event: String) {
        guard let path = env("CUTTINGS_TEST_STARTUP_EVENT_PATH") else { return }
        try? event.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Reads an environment variable, but only in UI-testing mode, so a
    /// production build can never be redirected by a stray variable.
    private static func env(_ key: String) -> String? {
        guard isUITesting,
              let value = ProcessInfo.processInfo.environment[key],
              !value.isEmpty
        else { return nil }
        return value
    }
}
