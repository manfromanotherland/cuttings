// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The platform adapter only requests iCloud downloads. Rust decides what a
/// capture means, validates its bytes, and owns every import and source removal.
enum InboxFileAvailability {
    enum ItemAvailability {
        case available
        case needsDownload
        case ignored
    }

    static func deferredNames(
        in inbox: URL,
        inspect: (URL) throws -> ItemAvailability = inspect,
        requestDownload: (URL) throws -> Void = FileManager.default.startDownloadingUbiquitousItem
    ) throws -> [String] {
        let values = try inbox.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName, userInfo: [NSFilePathErrorKey: inbox.path])
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        return files.compactMap { file in
            do {
                guard try inspect(file) == .needsDownload else { return nil }
                // An offline provider may reject the request. Leave the file
                // deferred either way; a later pass can request it again.
                try? requestDownload(file)
                return file.lastPathComponent
            } catch {
                // Unavailable metadata is not evidence that the bytes are safe
                // to consume. Keep this item while allowing other files through.
                return file.lastPathComponent
            }
        }
    }

    static func inspect(_ url: URL) throws -> ItemAvailability {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])
        guard values.isSymbolicLink != true, values.isDirectory != true else { return .ignored }
        if values.isUbiquitousItem == true {
            return values.ubiquitousItemDownloadingStatus == .current ? .available : .needsDownload
        }
        return values.isRegularFile == true ? .available : .ignored
    }
}

enum InboxRetrySchedule {
    /// Continue checking pending provider files without spinning on an offline
    /// device. FSEvents and the manual check can still wake the importer sooner.
    static func delay(attempt: Int) -> Duration {
        switch attempt {
        case ...0: .seconds(2)
        case 1: .seconds(5)
        case 2: .seconds(10)
        default: .seconds(30)
        }
    }
}
