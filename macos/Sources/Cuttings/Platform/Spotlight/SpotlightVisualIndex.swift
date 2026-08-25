// SPDX-License-Identifier: GPL-3.0-or-later

import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// A private, rebuildable semantic-media mirror for Cuttings images.
///
/// Source library URLs are opened only while a derived, oriented sRGB
/// thumbnail is created. Spotlight receives the Application Support thumbnail
/// URL, so it never needs to retain access to a security-scoped library URL.
actor SpotlightVisualIndex: SpotlightVisualIndexing {
    nonisolated static let indexName = "CuttingsVisualContent"
    nonisolated static let domainIdentifier = "is.edmundo.cuttings.visual-content"

    private static let itemIdentifierPrefix = "cuttings-visual:"
    private static let defaultMaximumResultCount = 2_000

    private let cacheRootURL: URL
    private let maximumThumbnailPixelSize: Int
    private let index: CSSearchableIndex
    private let manifestStore: SpotlightThumbnailManifestStore

    private var isReconciling = false
    private var reconciliationWaiters: [CheckedContinuation<Void, Never>] = []
    private var latestReconciliationGeneration = 0
    private var hasPerformedBootRepair = false

    init(cacheRootURL: URL? = nil, maximumThumbnailPixelSize: Int = 1_024) {
        let root = cacheRootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cuttings", isDirectory: true)
            .appendingPathComponent("SpotlightVisualContent", isDirectory: true)

        self.cacheRootURL = root
        self.maximumThumbnailPixelSize = max(128, maximumThumbnailPixelSize)
        index = CSSearchableIndex(name: Self.indexName)
        manifestStore = SpotlightThumbnailManifestStore(rootURL: root)
    }

    func reconcile(
        _ assets: [SpotlightVisualAsset]
    ) async throws -> SpotlightReconciliationResult {
        guard #available(macOS 15.0, *), CSSearchableIndex.isIndexingAvailable() else {
            return .unavailable
        }

        latestReconciliationGeneration &+= 1
        let generation = latestReconciliationGeneration
        await acquireReconciliation()
        defer { releaseReconciliation() }
        try requireCurrentReconciliation(generation)

        return try await reconcileAvailable(assets, generation: generation)
    }

    func search(_ query: String, limit: Int) async throws -> [String] {
        guard #available(macOS 15.0, *), CSSearchableIndex.isIndexingAvailable() else {
            return []
        }

        let queryString = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryString.isEmpty, limit > 0 else { return [] }
        return try await searchAvailable(
            queryString,
            limit: min(limit, Self.defaultMaximumResultCount)
        )
    }

    @available(macOS 15.0, *)
    private func reconcileAvailable(
        _ assets: [SpotlightVisualAsset],
        generation: Int
    ) async throws -> SpotlightReconciliationResult {
        var didMutateSpotlight = false
        do {
            let existingManifest: SpotlightThumbnailManifest
            var requiresFullRepair = !hasPerformedBootRepair
            do {
                switch try manifestStore.load() {
                case .missing:
                    requiresFullRepair = true
                    didMutateSpotlight = true
                    try await deleteDomain()
                    try requireCurrentReconciliation(generation)
                    try manifestStore.clearDerivedFiles()
                    existingManifest = .empty
                case let .present(manifest):
                    existingManifest = manifest
                }
            } catch SpotlightVisualIndexError.invalidManifest {
                requiresFullRepair = true
                didMutateSpotlight = true
                try await deleteDomain()
                try requireCurrentReconciliation(generation)
                try manifestStore.clearDerivedFiles()
                existingManifest = .empty
            }

            let availableFilenames = try manifestStore.thumbnailFilenames()
            let plan = try SpotlightReconciliationPlan.make(
                existing: existingManifest,
                desired: assets,
                availableThumbnailFilenames: availableFilenames,
                includeUnchangedDonations: requiresFullRepair
            )

            var failedThumbnailReadingIDs = Set<String>()
            for upsert in plan.upserts where upsert.needsThumbnail {
                let destinationURL = cacheRootURL.appendingPathComponent(
                    upsert.thumbnailFilename,
                    isDirectory: false
                )
                let sourceURL = upsert.asset.assetURL
                let maximumPixelSize = maximumThumbnailPixelSize
                do {
                    try await Task.detached(priority: .utility) {
                        try SpotlightThumbnailRenderer.writeThumbnail(
                            from: sourceURL,
                            to: destinationURL,
                            maximumPixelDimension: maximumPixelSize
                        )
                    }.value
                    try requireCurrentReconciliation(generation)
                } catch {
                    // Detached work does not inherit task cancellation. Always
                    // re-check the generation before treating a source-local
                    // decode failure as isolated and continuing the batch.
                    try requireCurrentReconciliation(generation)
                    failedThumbnailReadingIDs.insert(upsert.asset.readingID)
                }
            }

            try requireCurrentReconciliation(generation)
            let commit = plan.committing(
                excludingReadingIDs: failedThumbnailReadingIDs
            )
            let searchableItems = commit.upserts.map(makeSearchableItem)
            for chunk in searchableItems.chunked(maximumCount: 100) {
                try requireCurrentReconciliation(generation)
                didMutateSpotlight = true
                try await indexSearchableItems(chunk)
                try requireCurrentReconciliation(generation)
            }

            let deletedIdentifiers = commit.deletedReadingIDs.map(Self.itemIdentifier)
            for chunk in deletedIdentifiers.chunked(maximumCount: 100) {
                didMutateSpotlight = true
                try await deleteSearchableItems(withIdentifiers: chunk)
                try requireCurrentReconciliation(generation)
            }

            // No actor suspension is allowed between the final generation
            // check and committing the local manifest/cache state.
            try requireCurrentReconciliation(generation)
            try manifestStore.save(commit.manifest)
            try manifestStore.deleteThumbnails(named: commit.obsoleteThumbnailFilenames)
            hasPerformedBootRepair = true

            return SpotlightReconciliationResult(
                isAvailable: true,
                indexedCount: commit.upserts.count,
                deletedCount: commit.deletedReadingIDs.count,
                unchangedCount: plan.unchangedCount
            )
        } catch {
            // A newer generation can arrive while a Spotlight callback is in
            // flight. If any index mutation may already have landed, discard
            // the whole disposable mirror so the waiting newest generation
            // necessarily rebuilds it instead of trusting a stale manifest.
            if didMutateSpotlight {
                hasPerformedBootRepair = false
                try? await deleteDomain()
                try? manifestStore.clearDerivedFiles()
            }
            throw error
        }
    }

    @available(macOS 15.0, *)
    private func searchAvailable(_ queryString: String, limit: Int) async throws -> [String] {
        CSUserQuery.prepare()

        let context = CSUserQueryContext()
        context.enableRankedResults = true
        context.maxResultCount = limit
        context.maxRankedResultCount = limit
        context.maxSuggestionCount = 0
        context.fetchAttributes = ["domainIdentifier"]
        context.filterQueries = ["domainIdentifier=\"\(Self.domainIdentifier)\""]

        let userQuery = CSUserQuery(
            userQueryString: queryString,
            userQueryContext: context
        )
        let cancellation = SpotlightUserQueryCancellation(query: userQuery)
        let items: [CSUserQuery.Item] = try await withTaskCancellationHandler {
            var foundItems: [CSUserQuery.Item] = []
            for try await response in userQuery.responses {
                try Task.checkCancellation()
                guard case let .item(item) = response else { continue }
                foundItems.append(item)
            }
            return foundItems
        } onCancel: {
            cancellation.cancel()
        }

        var seen = Set<String>()
        return items.sorted {
            $0.item.compare(byRank: $1.item) == .orderedAscending
        }.compactMap { item in
            let identifier = item.item.uniqueIdentifier
            guard identifier.hasPrefix(Self.itemIdentifierPrefix) else { return nil }
            let readingID = String(identifier.dropFirst(Self.itemIdentifierPrefix.count))
            guard !readingID.isEmpty, seen.insert(readingID).inserted else { return nil }
            return readingID
        }
    }

    @available(macOS 15.0, *)
    private func makeSearchableItem(
        _ upsert: SpotlightReconciliationPlan.Upsert
    ) -> CSSearchableItem {
        let thumbnailURL = cacheRootURL.appendingPathComponent(
            upsert.thumbnailFilename,
            isDirectory: false
        )
        let attributes = CSSearchableItemAttributeSet(contentType: .png)
        attributes.title = upsert.asset.displayTitle ?? "Cutting"
        attributes.contentURL = thumbnailURL
        attributes.thumbnailURL = thumbnailURL
        attributes.domainIdentifier = Self.domainIdentifier

        let item = CSSearchableItem(
            uniqueIdentifier: Self.itemIdentifier(upsert.asset.readingID),
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
        // The first reconciliation in this process performs a full repair;
        // later reconciliations donate only changed items while retaining
        // non-update upsert semantics for those donations.
        item.isUpdate = false
        item.expirationDate = .distantFuture
        return item
    }

    private nonisolated static func itemIdentifier(_ readingID: String) -> String {
        itemIdentifierPrefix + readingID
    }

    private func acquireReconciliation() async {
        if !isReconciling {
            isReconciling = true
            return
        }
        await withCheckedContinuation { continuation in
            reconciliationWaiters.append(continuation)
        }
    }

    private func releaseReconciliation() {
        if reconciliationWaiters.isEmpty {
            isReconciling = false
        } else {
            reconciliationWaiters.removeFirst().resume()
        }
    }

    private func requireCurrentReconciliation(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == latestReconciliationGeneration else {
            throw CancellationError()
        }
    }

    @available(macOS 15.0, *)
    private func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        guard !items.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @available(macOS 15.0, *)
    private func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @available(macOS 15.0, *)
    private func deleteDomain() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Core Spotlight documents `cancel()` as callable when input changes, but its
/// Objective-C query class has no Swift Sendable annotation. The cancellation
/// handler is the only cross-executor use of this reference.
private final class SpotlightUserQueryCancellation: @unchecked Sendable {
    private let query: CSUserQuery

    init(query: CSUserQuery) {
        self.query = query
    }

    func cancel() {
        query.cancel()
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        let size = Swift.max(1, maximumCount)
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start ..< Swift.min(start + size, count)])
        }
    }
}
