// SPDX-License-Identifier: GPL-3.0-or-later

import CoreSpotlight
import CryptoKit
import Foundation

struct SpotlightThumbnailManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var entries: [String: SpotlightThumbnailManifestEntry]

    static let empty = SpotlightThumbnailManifest(entries: [:])
}

struct SpotlightThumbnailManifestEntry: Codable, Equatable, Sendable {
    let assetHash: String
    let displayTitle: String?
    let thumbnailFilename: String
}

enum SpotlightManifestLoadResult: Equatable {
    case missing
    case present(SpotlightThumbnailManifest)
}

enum SpotlightThumbnailNaming {
    static func filename(readingID: String, assetHash: String) -> String {
        let identity = Data("\(readingID)\u{0}\(assetHash)".utf8)
        let digest = SHA256.hash(data: identity)
        return digest.map { String(format: "%02x", $0) }.joined() + ".png"
    }
}

struct SpotlightReconciliationPlan: Equatable {
    struct Upsert: Equatable {
        let asset: SpotlightVisualAsset
        let thumbnailFilename: String
        let needsThumbnail: Bool
    }

    private struct Draft {
        var upserts: [Upsert] = []
        var entries: [String: SpotlightThumbnailManifestEntry] = [:]
        var obsoleteFilenames = Set<String>()
        var unchangedCount = 0

        mutating func add(
            _ asset: SpotlightVisualAsset,
            oldEntry: SpotlightThumbnailManifestEntry?,
            availableFilenames: Set<String>,
            includeUnchangedDonations: Bool
        ) {
            let filename = SpotlightThumbnailNaming.filename(
                readingID: asset.readingID,
                assetHash: asset.assetHash
            )
            entries[asset.readingID] = SpotlightThumbnailManifestEntry(
                assetHash: asset.assetHash,
                displayTitle: asset.displayTitle,
                thumbnailFilename: filename
            )
            let needsThumbnail = oldEntry?.assetHash != asset.assetHash
                || oldEntry?.thumbnailFilename != filename
                || !availableFilenames.contains(filename)
            let needsMetadataDonation = oldEntry?.displayTitle != asset.displayTitle
            if includeUnchangedDonations || needsThumbnail || needsMetadataDonation {
                upserts.append(Upsert(
                    asset: asset,
                    thumbnailFilename: filename,
                    needsThumbnail: needsThumbnail
                ))
            }
            if !needsThumbnail, oldEntry?.displayTitle == asset.displayTitle {
                unchangedCount += 1
            }
            if let oldFilename = oldEntry?.thumbnailFilename, oldFilename != filename {
                obsoleteFilenames.insert(oldFilename)
            }
        }

        mutating func includeDeletions(
            _ readingIDs: [String],
            from manifest: SpotlightThumbnailManifest
        ) {
            for readingID in readingIDs {
                if let filename = manifest.entries[readingID]?.thumbnailFilename {
                    obsoleteFilenames.insert(filename)
                }
            }
        }
    }

    let upserts: [Upsert]
    let deletedReadingIDs: [String]
    let obsoleteThumbnailFilenames: [String]
    let unchangedCount: Int
    let resultingManifest: SpotlightThumbnailManifest

    func committing(
        excludingReadingIDs failedReadingIDs: Set<String>
    ) -> SpotlightReconciliationCommit {
        guard !failedReadingIDs.isEmpty else {
            return SpotlightReconciliationCommit(
                upserts: upserts,
                deletedReadingIDs: deletedReadingIDs,
                obsoleteThumbnailFilenames: obsoleteThumbnailFilenames,
                manifest: resultingManifest
            )
        }

        var manifest = resultingManifest
        failedReadingIDs.forEach { manifest.entries.removeValue(forKey: $0) }

        let failedFilenames = upserts
            .filter { failedReadingIDs.contains($0.asset.readingID) }
            .map(\.thumbnailFilename)
        let deletions = Set(deletedReadingIDs).union(failedReadingIDs)
        let obsoleteFilenames = Set(obsoleteThumbnailFilenames).union(failedFilenames)

        return SpotlightReconciliationCommit(
            upserts: upserts.filter { !failedReadingIDs.contains($0.asset.readingID) },
            deletedReadingIDs: deletions.sorted(),
            obsoleteThumbnailFilenames: obsoleteFilenames.sorted(),
            manifest: manifest
        )
    }

    static func make(
        existing: SpotlightThumbnailManifest,
        desired assets: [SpotlightVisualAsset],
        availableThumbnailFilenames: Set<String>,
        includeUnchangedDonations: Bool
    ) throws -> SpotlightReconciliationPlan {
        let desiredByReadingID = try normalizedAssets(assets)
        var draft = Draft()
        for asset in desiredByReadingID.values.sorted(by: assetOrder) {
            draft.add(
                asset,
                oldEntry: existing.entries[asset.readingID],
                availableFilenames: availableThumbnailFilenames,
                includeUnchangedDonations: includeUnchangedDonations
            )
        }
        let desiredReadingIDs = Set(desiredByReadingID.keys)
        let deletedReadingIDs = existing.entries.keys
            .filter { !desiredReadingIDs.contains($0) }
            .sorted()
        draft.includeDeletions(deletedReadingIDs, from: existing)
        let desiredFilenames = Set(draft.entries.values.map(\.thumbnailFilename))
        draft.obsoleteFilenames.formUnion(
            availableThumbnailFilenames.subtracting(desiredFilenames)
        )
        draft.obsoleteFilenames.subtract(desiredFilenames)

        return SpotlightReconciliationPlan(
            upserts: draft.upserts,
            deletedReadingIDs: deletedReadingIDs,
            obsoleteThumbnailFilenames: draft.obsoleteFilenames.sorted(),
            unchangedCount: draft.unchangedCount,
            resultingManifest: SpotlightThumbnailManifest(entries: draft.entries)
        )
    }

    private static func normalizedAssets(
        _ assets: [SpotlightVisualAsset]
    ) throws -> [String: SpotlightVisualAsset] {
        var result: [String: SpotlightVisualAsset] = [:]
        for asset in assets {
            let readingID = asset.readingID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !readingID.isEmpty else { throw SpotlightVisualIndexError.emptyReadingID }
            let assetHash = asset.assetHash.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !assetHash.isEmpty else {
                throw SpotlightVisualIndexError.emptyAssetHash(readingID: readingID)
            }
            guard result[readingID] == nil else {
                throw SpotlightVisualIndexError.duplicateReadingID(readingID)
            }
            let displayTitle = asset.displayTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[readingID] = SpotlightVisualAsset(
                readingID: readingID,
                assetHash: assetHash,
                assetURL: asset.assetURL.standardizedFileURL,
                displayTitle: displayTitle?.isEmpty == true ? nil : displayTitle
            )
        }
        return result
    }

    private static func assetOrder(
        _ lhs: SpotlightVisualAsset,
        _ rhs: SpotlightVisualAsset
    ) -> Bool {
        lhs.readingID < rhs.readingID
    }
}

struct SpotlightReconciliationCommit: Equatable {
    let upserts: [SpotlightReconciliationPlan.Upsert]
    let deletedReadingIDs: [String]
    let obsoleteThumbnailFilenames: [String]
    let manifest: SpotlightThumbnailManifest
}

struct SpotlightLoadedManifest {
    let manifest: SpotlightThumbnailManifest
    let requiresFullRepair: Bool
}

struct SpotlightThumbnailManifestStore {
    private static let manifestFilename = "manifest.json"

    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    var manifestURL: URL {
        rootURL.appendingPathComponent(Self.manifestFilename, isDirectory: false)
    }

    func load() throws -> SpotlightManifestLoadResult {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return .missing }

        let data = try Data(contentsOf: manifestURL)
        let manifest: SpotlightThumbnailManifest
        do {
            manifest = try JSONDecoder().decode(SpotlightThumbnailManifest.self, from: data)
        } catch {
            throw SpotlightVisualIndexError.invalidManifest
        }
        guard manifest.schemaVersion == SpotlightThumbnailManifest.currentSchemaVersion else {
            throw SpotlightVisualIndexError.invalidManifest
        }

        for (readingID, entry) in manifest.entries {
            guard !readingID.isEmpty,
                  !entry.assetHash.isEmpty,
                  entry.thumbnailFilename == URL(fileURLWithPath: entry.thumbnailFilename)
                  .lastPathComponent,
                  entry.thumbnailFilename.hasSuffix(".png")
            else {
                throw SpotlightVisualIndexError.invalidManifest
            }
        }
        return .present(manifest)
    }

    func save(_ manifest: SpotlightThumbnailManifest) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    func thumbnailFilenames() throws -> Set<String> {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return Set(urls.filter { $0.pathExtension.lowercased() == "png" }.map(\.lastPathComponent))
    }

    func deleteThumbnails(named filenames: some Sequence<String>) throws {
        for filename in filenames {
            guard filename == URL(fileURLWithPath: filename).lastPathComponent,
                  filename.hasSuffix(".png")
            else { continue }

            let url = rootURL.appendingPathComponent(filename, isDirectory: false)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    func clearDerivedFiles() throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for url in urls where url.pathExtension.lowercased() == "png"
            || url.lastPathComponent == Self.manifestFilename
            || url.lastPathComponent.hasPrefix(".thumbnail-")
        {
            try fileManager.removeItem(at: url)
        }
    }
}

/// Core Spotlight documents `cancel()` as callable when input changes, but its
/// Objective-C query class has no Swift Sendable annotation.
final class SpotlightUserQueryCancellation: @unchecked Sendable {
    private let query: CSUserQuery

    init(query: CSUserQuery) {
        self.query = query
    }

    func cancel() {
        query.cancel()
    }
}

extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        let size = Swift.max(1, maximumCount)
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start ..< Swift.min(start + size, count)])
        }
    }
}
