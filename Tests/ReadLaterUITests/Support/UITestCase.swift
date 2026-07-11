// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// Base class every UI test sits on. It gives each test an isolated temp library
/// (so tests never see each other's data), launches the app against it, and — on
/// teardown — terminates the app, destroys the temp library, and restores the
/// dev's real preferences. The dev's real library bookmark is never touched.
///
/// E2E-6 layers the fake-readings engine on top: a `launchApp(articles:)` overload
/// that seeds fixtures before launch, and a typed `Frontmatter` reader. This base
/// deliberately only knows how to launch an *empty* library.
class UITestCase: XCTestCase {
    /// The running app under test, set by a `launch*` call.
    private(set) var app: XCUIApplication!

    /// Library root the app was booted against (`<temp>/library`). For an
    /// onboarding launch it's the folder onboarding will scaffold.
    private(set) var libraryRoot: URL?

    /// Per-test temp directory (parent of `library/` and `index.db`); destroyed on
    /// teardown.
    private var tempRoot: URL?

    /// Pre-test values of the managed defaults keys, restored on teardown. The
    /// value is `String?`: `nil` means the key was unset before the test.
    private var defaultsSnapshot: [String: String?] = [:]

    // ── Lifecycle ───────────────────────────────────────────────────────────

    override func setUpWithError() throws {
        continueAfterFailure = false
        snapshotDefaults()
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        restoreDefaults()
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        tempRoot = nil
        libraryRoot = nil
    }

    // ── Launch ────────────────────────────────────────────────────────────

    /// Launch straight into the main view against a fresh, empty temp library.
    /// (E2E-6 adds an `articles:` overload that seeds fixtures before launch.)
    @discardableResult
    func launchApp(configure: (inout LaunchOptions) -> Void = { _ in }) throws -> XCUIApplication {
        let library = try makeEmptyLibrary()
        var options = LaunchOptions(
            libraryPath: library.root.path,
            dbPath: library.dbPath.path
        )
        configure(&options)
        app = AppLauncher.launch(options)
        XCTAssertTrue(
            app.byId(A11y.Sidebar.viewRow("all")).waitForExistence(timeout: 20),
            "Main view (sidebar) did not appear after launch."
        )
        return app
    }

    /// Launch into onboarding (no library configured). `onboardingPickPath` is
    /// pointed at a fresh temp folder, so clicking "Choose Library…" scaffolds
    /// *that* — keeping the flow testable without a system open panel.
    @discardableResult
    func launchOnboarding(configure: (inout LaunchOptions) -> Void = { _ in }) throws -> XCUIApplication {
        let base = try makeTempRoot()
        let pick = base.appendingPathComponent("library", isDirectory: true)
        libraryRoot = pick
        var options = LaunchOptions(
            dbPath: base.appendingPathComponent("index.db").path,
            onboardingPickPath: pick.path
        )
        configure(&options)
        app = AppLauncher.launch(options)
        XCTAssertTrue(
            app.byId(A11y.Onboarding.chooseLibrary).waitForExistence(timeout: 20),
            "Onboarding did not appear after launch."
        )
        return app
    }

    // ── On-disk assertions ────────────────────────────────────────────────

    /// Polls the on-disk article file for `id` until `predicate(contents)` holds
    /// or `timeout` elapses — the "file is the source of truth" check after a
    /// mutation. Reads `<libraryRoot>/articles/<id>.md` raw; E2E-6 adds a typed
    /// overload that hands the predicate a parsed `Frontmatter` instead.
    @discardableResult
    func waitForFrontmatter(
        id: String,
        timeout: TimeInterval = 8,
        _ predicate: (String) -> Bool
    ) -> Bool {
        guard let libraryRoot else {
            XCTFail("waitForFrontmatter called before a library was launched.")
            return false
        }
        let url = libraryRoot.appendingPathComponent("articles/\(id).md")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let contents = try? String(contentsOf: url, encoding: .utf8), predicate(contents) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    // ── Temp library ────────────────────────────────────────────────────────

    /// Creates a unique per-test temp directory and remembers it for teardown.
    private func makeTempRoot() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadLaterUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        tempRoot = base
        return base
    }

    /// Scaffolds an empty library (`articles/`, `assets/`, `highlights/`) with a
    /// sibling `index.db` path, matching the on-disk layout `TestLibrary` (E2E-6)
    /// will manage.
    private func makeEmptyLibrary() throws -> (root: URL, dbPath: URL) {
        let base = try makeTempRoot()
        let library = base.appendingPathComponent("library", isDirectory: true)
        for sub in ["articles", "assets", "highlights"] {
            try FileManager.default.createDirectory(
                at: library.appendingPathComponent(sub, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        libraryRoot = library
        return (library, base.appendingPathComponent("index.db"))
    }

    // ── Defaults isolation ──────────────────────────────────────────────────
    // The app writes preferences to the real `com.readlater.app` domain — only
    // the library and DB are redirected under test, never the defaults — so a
    // test that changes theme, font, or sort would otherwise leak into the dev's
    // own preferences. Snapshot the mutable keys before each test and restore
    // them after. `libraryBookmark` is deliberately absent: we never read, write,
    // or delete it, so the dev's real library pointer stays intact.

    private static let appDomain = "com.readlater.app"

    /// `(key, `defaults write` type flag)` for every preference the app mutates.
    private static let managedDefaults: [(key: String, type: String)] = [
        ("appearanceMode", "-string"),
        ("readerFont", "-string"),
        ("readerFontSize", "-int"),
        ("sortField", "-string"),
        ("sortAscending", "-bool"),
        ("sidebarLibraryExpanded", "-bool"),
        ("sidebarRatingsExpanded", "-bool"),
        ("sidebarTagsExpanded", "-bool"),
    ]

    private func snapshotDefaults() {
        defaultsSnapshot = [:]
        for (key, _) in Self.managedDefaults {
            // `updateValue` (not the subscript) so a `nil` reading is stored as
            // "present but unset" rather than removing the key entirely.
            defaultsSnapshot.updateValue(Self.runDefaults(["read", Self.appDomain, key]), forKey: key)
        }
    }

    private func restoreDefaults() {
        for (key, type) in Self.managedDefaults {
            // Outer `??` collapses the `String??` from the dictionary lookup;
            // inner value `nil` means the key was unset before the test.
            let previous = defaultsSnapshot[key] ?? nil
            if let previous {
                _ = Self.runDefaults(["write", Self.appDomain, key, type, previous])
            } else {
                _ = Self.runDefaults(["delete", Self.appDomain, key])
            }
        }
    }

    /// Runs `/usr/bin/defaults` and returns trimmed stdout, or `nil` on a
    /// non-zero exit (e.g. reading a key that isn't set).
    @discardableResult
    private static func runDefaults(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (output?.isEmpty ?? true) ? nil : output
    }
}
