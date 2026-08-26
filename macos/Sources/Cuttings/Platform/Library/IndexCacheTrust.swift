// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Proves that the disposable index belongs to the restored library and is the
/// exact database file that completed a rebuild. The file identity prevents a
/// newly recreated empty SQLite file from masquerading as a warm cache.
enum IndexCacheTrust {
    enum Status {
        case trusted
        case legacy
        case unavailable
    }

    private struct Marker: Codable {
        let libraryPath: String
        let device: UInt64
        let inode: UInt64
    }

    static func status(libraryURL: URL, databasePath: String) -> Status {
        guard FileManager.default.fileExists(atPath: databasePath) else { return .unavailable }

        if let testPath = TestHooks.trustedCachedLibraryPath {
            return URL(fileURLWithPath: testPath).standardizedFileURL.path
                == libraryURL.standardizedFileURL.path ? .trusted : .unavailable
        }

        let markerURL = markerURL(databasePath: databasePath)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            guard let data = try? Data(contentsOf: markerURL),
                  let marker = try? JSONDecoder().decode(Marker.self, from: data),
                  let identity = databaseIdentity(databasePath: databasePath) else {
                return .unavailable
            }
            let matches = URL(fileURLWithPath: marker.libraryPath).standardizedFileURL.path
                    == libraryURL.standardizedFileURL.path
                && marker.device == identity.device
                && marker.inode == identity.inode
            return matches ? .trusted : .unavailable
        }
        guard !TestHooks.isUITesting else { return .unavailable }

        // One-time migration for indexes created before the ready marker
        // existed. The first successful rebuild binds future trust to this DB's
        // file identity, so a deleted/recreated empty index is never reused.
        guard let recordedPath = (try? String(
            contentsOf: libraryPathConfigURL,
            encoding: .utf8
        ))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !recordedPath.isEmpty else { return .unavailable }

        let matches = URL(fileURLWithPath: recordedPath).standardizedFileURL.path
            == libraryURL.standardizedFileURL.path
        return matches ? .legacy : .unavailable
    }

    /// One-time validation for pre-marker caches. Matching the indexed count to
    /// the library's reading files rejects recreated, truncated, or wrong DBs.
    static func legacyCacheMatches(libraryURL: URL, bridge: CoreBridge) async -> Bool {
        async let cachedCount = try? await bridge.readingCount()
        async let fileCount = readingFileCount(libraryURL: libraryURL)
        guard let indexed = await cachedCount,
              let onDisk = await fileCount else { return false }
        return indexed == onDisk
    }

    static func record(libraryURL: URL, databasePath: String) {
        guard let identity = databaseIdentity(databasePath: databasePath) else { return }
        let marker = Marker(
            libraryPath: libraryURL.standardizedFileURL.path,
            device: identity.device,
            inode: identity.inode
        )
        guard let data = try? JSONEncoder().encode(marker) else { return }
        try? data.write(to: markerURL(databasePath: databasePath), options: .atomic)
    }

    private static var libraryPathConfigURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/cuttings/library")
    }

    private static func markerURL(databasePath: String) -> URL {
        URL(fileURLWithPath: databasePath).appendingPathExtension("ready")
    }

    private static func databaseIdentity(
        databasePath: String
    ) -> (device: UInt64, inode: UInt64)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: databasePath),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return (device.uint64Value, inode.uint64Value)
    }

    private static func readingFileCount(libraryURL: URL) async -> UInt64? {
        await Task.detached(priority: .userInitiated) {
            readingFileCountSync(libraryURL: libraryURL)
        }.value
    }

    private static func readingFileCountSync(libraryURL: URL) -> UInt64? {
        let articlesURL = libraryURL.appendingPathComponent("articles", isDirectory: true)
        guard FileManager.default.fileExists(atPath: articlesURL.path) else { return 0 }
        guard let files = FileManager.default.enumerator(
            at: articlesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var count: UInt64 = 0
        for case let fileURL as URL in files where fileURL.lastPathComponent == "article.md" {
            count += 1
        }
        return count
    }
}
