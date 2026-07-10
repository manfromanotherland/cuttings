// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Creates the expected subdirectory layout inside the library root.
enum LibrarySetup {
    static let subdirectories = ["articles", "assets"]

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
