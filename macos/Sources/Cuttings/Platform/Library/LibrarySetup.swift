// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Creates the expected subdirectory layout inside the library root.
///
/// `articles/` and `inbox/` are scaffolded so a brand-new library can be watched
/// before the first save or shared file arrives. Everything else for a reading — its `assets/` and
/// `highlights.md` — lives inside that reading's own folder
/// (`articles/<prefix>/<id>/`) and is created on demand when the reading is
/// written, so there is no top-level `assets/` or `highlights/` directory.
enum LibrarySetup {
    static let subdirectories = ["articles", "inbox"]

    static func scaffold(at url: URL) throws {
        let fileManager = FileManager.default
        for dir in subdirectories {
            let sub = url.appendingPathComponent(dir, isDirectory: true)
            if fileManager.fileExists(atPath: sub.path) {
                let values = try sub.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: sub.path])
                }
            } else {
                try fileManager.createDirectory(at: sub, withIntermediateDirectories: true)
            }
        }
    }
}
