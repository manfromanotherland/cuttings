// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `LibrarySetup` scaffolds the library's on-disk layout: it creates the
/// `articles` and `assets` subdirectories under the chosen root and is safe to
/// re-run. Exercised against a throwaway temp directory, never a real library.
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

    func testScaffoldCreatesArticlesAndAssets() throws {
        try LibrarySetup.scaffold(at: root)
        for dir in ["articles", "assets"] {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(dir).path, isDirectory: &isDirectory
            )
            XCTAssertTrue(exists && isDirectory.boolValue, "expected \(dir)/ to be created")
        }
    }

    func testScaffoldIsIdempotent() throws {
        try LibrarySetup.scaffold(at: root)
        XCTAssertNoThrow(try LibrarySetup.scaffold(at: root))
    }
}
