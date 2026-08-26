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
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

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

    /// Holds only the file reconciliation phase, after a trusted cached board
    /// has had a chance to publish. Used by warm-start regression checks.
    static var libraryReconciliationDelayNanoseconds: UInt64? {
        env("CUTTINGS_TEST_LIBRARY_RECONCILIATION_DELAY_MS")
            .flatMap(UInt64.init)
            .map { $0 * 1_000_000 }
    }

    /// Declares which redirected library owns the redirected cached index.
    /// Production derives this trust marker from ~/.config/cuttings/library.
    static var trustedCachedLibraryPath: String? {
        env("CUTTINGS_TEST_TRUSTED_CACHE_LIBRARY")
    }

    /// Records an event for the command-line startup regression probes. A
    /// single latest-event path keeps the tiny toolbar/timing probes simple;
    /// an events directory retains named snapshots for reconciliation checks.
    @MainActor
    static func recordStartupEvent(_ event: String, details: String? = nil) {
        let contents = details ?? event
        if let path = env("CUTTINGS_TEST_STARTUP_EVENT_PATH") {
            try? contents.write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let directory = env("CUTTINGS_TEST_STARTUP_EVENTS_DIR") {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(event)
            try? contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Captures enough board identity to prove that a cached snapshot was shown
    /// first and the later file reconciliation replaced it correctly.
    @MainActor
    static func recordStartupSnapshot(_ event: String, rows: [ReadingRow]) {
        guard env("CUTTINGS_TEST_STARTUP_EVENTS_DIR") != nil else { return }
        let details = [
            String(rows.count),
            rows.first?.id ?? "",
            rows.map(\.id).joined(separator: ",")
        ].joined(separator: "\n")
        recordStartupEvent(event, details: details)
    }

    @MainActor
    static func recordVisibleCard(id: String) {
        guard env("CUTTINGS_TEST_STARTUP_EVENTS_DIR") != nil else { return }
        let safeID = id.map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        recordStartupEvent("card-visible-\(String(safeID))", details: id)
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
