// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `LibrarySetup` scaffolds the library's on-disk layout: it creates the
/// `articles` subdirectory under the chosen root (assets live inside each
/// reading's folder, so there is no top-level `assets/`) and is safe to re-run.
/// Exercised against a throwaway temp directory, never a real library.
final class LibrarySetupTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("librarysetup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testScaffoldCreatesArticles() throws {
        try LibrarySetup.scaffold(at: root)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: root.appendingPathComponent("articles").path, isDirectory: &isDirectory
        )
        XCTAssertTrue(exists && isDirectory.boolValue, "expected articles/ to be created")
    }

    func testScaffoldDoesNotCreateTopLevelAssets() throws {
        try LibrarySetup.scaffold(at: root)

        // Assets live inside each reading's folder, so no top-level assets/ dir.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("assets").path),
            "there should be no top-level assets/ directory"
        )
    }

    func testScaffoldIsIdempotent() throws {
        try LibrarySetup.scaffold(at: root)
        XCTAssertNoThrow(try LibrarySetup.scaffold(at: root))
    }
}
