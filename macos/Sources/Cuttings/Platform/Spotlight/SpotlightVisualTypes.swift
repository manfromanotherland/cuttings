// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One canonical local image to mirror into the disposable Spotlight index.
struct SpotlightVisualAsset: Equatable, Sendable {
    let readingID: String
    let assetHash: String
    let assetURL: URL
    let displayTitle: String?

    init(
        readingID: String,
        assetHash: String,
        assetURL: URL,
        displayTitle: String? = nil
    ) {
        self.readingID = readingID
        self.assetHash = assetHash
        self.assetURL = assetURL
        self.displayTitle = displayTitle
    }
}

struct SpotlightReconciliationResult: Equatable, Sendable {
    let isAvailable: Bool
    let indexedCount: Int
    let deletedCount: Int
    let unchangedCount: Int

    static let unavailable = SpotlightReconciliationResult(
        isAvailable: false,
        indexedCount: 0,
        deletedCount: 0,
        unchangedCount: 0
    )
}

/// The seam through which Cuttings maintains and queries its visual Spotlight
/// mirror. Both methods are intentional no-ops on macOS 14.
protocol SpotlightVisualIndexing: Sendable {
    func reconcile(
        _ assets: [SpotlightVisualAsset]
    ) async throws -> SpotlightReconciliationResult

    func search(_ query: String, limit: Int) async throws -> [String]
}

enum SpotlightVisualIndexError: Error, LocalizedError, Sendable {
    case emptyReadingID
    case emptyAssetHash(readingID: String)
    case duplicateReadingID(String)
    case invalidManifest
    case thumbnailEncodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyReadingID:
            "A Spotlight visual asset has an empty reading id."
        case let .emptyAssetHash(readingID):
            "The Spotlight visual asset for \(readingID) has an empty asset hash."
        case let .duplicateReadingID(readingID):
            "More than one Spotlight visual asset uses reading id \(readingID)."
        case .invalidManifest:
            "The local Spotlight visual manifest is invalid."
        case .thumbnailEncodingFailed:
            "The derived Spotlight thumbnail could not be encoded."
        }
    }
}
