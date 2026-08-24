// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Creates the expected subdirectory layout inside the library root.
///
/// Only `articles/` is scaffolded: it's what the folder watcher watches and the
/// scanner walks, so pre-creating it lets a brand-new library be watched before
/// the first save. Everything else for a reading — its `assets/` and
/// `highlights.md` — lives inside that reading's own folder
/// (`articles/<prefix>/<id>/`) and is created on demand when the reading is
/// written, so there is no top-level `assets/` or `highlights/` directory.
enum LibrarySetup {
    static let subdirectories = ["articles"]

    static func scaffold(at url: URL) throws {
        let fileManager = FileManager.default
        for dir in subdirectories {
            let sub = url.appendingPathComponent(dir, isDirectory: true)
            if !fileManager.fileExists(atPath: sub.path) {
                try fileManager.createDirectory(at: sub, withIntermediateDirectories: true)
            }
        }
    }
}
