// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The `UserDefaults` store the app persists its per-device preferences to
/// (theme, reader typography, card size, board sort, and filters).
///
/// In production this is `.standard`. Under UI testing, when the harness passes a
/// suite name via `CUTTINGS_TEST_DEFAULTS`, it's a throwaway suite in that name
/// instead — so a test that changes a preference never reads or writes the real
/// `is.edmundo.cuttings` domain, and the dev's own preferences stay untouched. The
/// harness creates the suite per test and destroys it on teardown.
///
/// Every `@AppStorage` for a preference key passes `store: AppDefaults.store`, and
/// the sort keys written from `AppState` go through it too, so there is a single
/// redirection point.
enum AppDefaults {
    /// `UserDefaults` is thread-safe but not `Sendable`, so the Swift 6 concurrency
    /// checker flags a shared `static let`; `nonisolated(unsafe)` opts out (the type
    /// is safe to touch from any thread).
    nonisolated(unsafe) static let store: UserDefaults = {
        if let suite = TestHooks.defaultsSuiteName, let store = UserDefaults(suiteName: suite) {
            return store
        }
        return .standard
    }()
}
