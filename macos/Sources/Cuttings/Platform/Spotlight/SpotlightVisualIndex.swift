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
    private static let defaultMaximumResultCount = 2000

    private let cacheRootURL: URL
    private let maximumThumbnailPixelSize: Int
    private let index: CSSearchableIndex
    private let manifestStore: SpotlightThumbnailManifestStore

    private var isReconciling = false
    private var reconciliationWaiters: [CheckedContinuation<Void, Never>] = []
    private var latestReconciliationGeneration = 0
    private var hasPerformedBootRepair = false

    init(cacheRootURL: URL? = nil, maximumThumbnailPixelSize: Int = 1024) {
        let root = cacheRootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cuttings", isDirectory: true)
            .appendingPathComponent("SpotlightVisualContent", isDirectory: true)

        self.cacheRootURL = root
        self.maximumThumbnailPixelSize = max(128, maximumThumbnailPixelSize)
        index = CSSearchableIndex(name: Self.indexName)
        manifestStore = SpotlightThumbnailManifestStore(rootURL: root)
    }

    func reconcile(_ assets: [SpotlightVisualAsset]) async throws -> SpotlightReconciliationResult {
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
}

@available(macOS 15.0, *)
private extension SpotlightVisualIndex {
    func reconcileAvailable(
        _ assets: [SpotlightVisualAsset],
        generation: Int
    ) async throws -> SpotlightReconciliationResult {
        var didMutateSpotlight = false
        do {
            return try await performReconciliation(
                assets,
                generation: generation,
                didMutateSpotlight: &didMutateSpotlight
            )
        } catch {
            if didMutateSpotlight {
                hasPerformedBootRepair = false
                try? await deleteDomain()
                try? manifestStore.clearDerivedFiles()
            }
            throw error
        }
    }

    func performReconciliation(
        _ assets: [SpotlightVisualAsset], generation: Int, didMutateSpotlight: inout Bool
    ) async throws -> SpotlightReconciliationResult {
        let loaded = try await loadManifest(
            generation: generation, didMutateSpotlight: &didMutateSpotlight
        )
        let plan = try makePlan(assets, loaded: loaded)
        let failedReadingIDs = try await prepareThumbnails(for: plan, generation: generation)
        try requireCurrentReconciliation(generation)
        let commit = plan.committing(excludingReadingIDs: failedReadingIDs)
        if !commit.upserts.isEmpty || !commit.deletedReadingIDs.isEmpty {
            didMutateSpotlight = true
        }
        try await apply(commit, generation: generation)
        try commitManifest(commit, generation: generation)
        return SpotlightReconciliationResult(
            isAvailable: true,
            indexedCount: commit.upserts.count,
            deletedCount: commit.deletedReadingIDs.count,
            unchangedCount: plan.unchangedCount
        )
    }

    func loadManifest(
        generation: Int,
        didMutateSpotlight: inout Bool
    ) async throws -> SpotlightLoadedManifest {
        do {
            switch try manifestStore.load() {
            case .missing:
                didMutateSpotlight = true
                try await resetDerivedState(generation: generation)
                return SpotlightLoadedManifest(manifest: .empty, requiresFullRepair: true)
            case let .present(manifest):
                return SpotlightLoadedManifest(
                    manifest: manifest,
                    requiresFullRepair: !hasPerformedBootRepair
                )
            }
        } catch SpotlightVisualIndexError.invalidManifest {
            didMutateSpotlight = true
            try await resetDerivedState(generation: generation)
            return SpotlightLoadedManifest(manifest: .empty, requiresFullRepair: true)
        }
    }

    func resetDerivedState(generation: Int) async throws {
        try await deleteDomain()
        try requireCurrentReconciliation(generation)
        try manifestStore.clearDerivedFiles()
    }

    func makePlan(
        _ assets: [SpotlightVisualAsset], loaded: SpotlightLoadedManifest
    ) throws -> SpotlightReconciliationPlan {
        try SpotlightReconciliationPlan.make(
            existing: loaded.manifest,
            desired: assets,
            availableThumbnailFilenames: manifestStore.thumbnailFilenames(),
            includeUnchangedDonations: loaded.requiresFullRepair
        )
    }

    func prepareThumbnails(
        for plan: SpotlightReconciliationPlan, generation: Int
    ) async throws -> Set<String> {
        var failedReadingIDs = Set<String>()
        for upsert in plan.upserts where upsert.needsThumbnail {
            do {
                try await renderThumbnail(for: upsert)
                try requireCurrentReconciliation(generation)
            } catch {
                try requireCurrentReconciliation(generation)
                failedReadingIDs.insert(upsert.asset.readingID)
            }
        }
        return failedReadingIDs
    }

    func renderThumbnail(for upsert: SpotlightReconciliationPlan.Upsert) async throws {
        let destinationURL = cacheRootURL.appendingPathComponent(
            upsert.thumbnailFilename,
            isDirectory: false
        )
        let sourceURL = upsert.asset.assetURL
        let maximumPixelSize = maximumThumbnailPixelSize
        try await Task.detached(priority: .utility) {
            try SpotlightThumbnailRenderer.writeThumbnail(
                from: sourceURL,
                to: destinationURL,
                maximumPixelDimension: maximumPixelSize
            )
        }.value
    }

    func apply(_ commit: SpotlightReconciliationCommit, generation: Int) async throws {
        for chunk in commit.upserts.map(makeSearchableItem).chunked(maximumCount: 100) {
            try requireCurrentReconciliation(generation)
            try await indexSearchableItems(chunk)
            try requireCurrentReconciliation(generation)
        }
        let deletedIdentifiers = commit.deletedReadingIDs.map(Self.itemIdentifier)
        for chunk in deletedIdentifiers.chunked(maximumCount: 100) {
            try await deleteSearchableItems(withIdentifiers: chunk)
            try requireCurrentReconciliation(generation)
        }
    }

    func commitManifest(_ commit: SpotlightReconciliationCommit, generation: Int) throws {
        try requireCurrentReconciliation(generation)
        try manifestStore.save(commit.manifest)
        try manifestStore.deleteThumbnails(named: commit.obsoleteThumbnailFilenames)
        hasPerformedBootRepair = true
    }

    func searchAvailable(_ queryString: String, limit: Int) async throws -> [String] {
        CSUserQuery.prepare()
        let userQuery = CSUserQuery(
            userQueryString: queryString,
            userQueryContext: makeQueryContext(limit: limit)
        )
        return try await readingIDs(from: collectItems(from: userQuery))
    }

    func makeQueryContext(limit: Int) -> CSUserQueryContext {
        let context = CSUserQueryContext()
        context.enableRankedResults = true
        context.maxResultCount = limit
        context.maxRankedResultCount = limit
        context.maxSuggestionCount = 0
        context.fetchAttributes = ["domainIdentifier"]
        context.filterQueries = ["domainIdentifier=\"\(Self.domainIdentifier)\""]
        return context
    }

    func collectItems(from userQuery: CSUserQuery) async throws -> [CSUserQuery.Item] {
        let cancellation = SpotlightUserQueryCancellation(query: userQuery)
        return try await withTaskCancellationHandler {
            var items: [CSUserQuery.Item] = []
            for try await response in userQuery.responses {
                try Task.checkCancellation()
                guard case let .item(item) = response else { continue }
                items.append(item)
            }
            return items
        } onCancel: {
            cancellation.cancel()
        }
    }

    func readingIDs(from items: [CSUserQuery.Item]) -> [String] {
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

    func makeSearchableItem(_ upsert: SpotlightReconciliationPlan.Upsert) -> CSSearchableItem {
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
        item.isUpdate = false
        item.expirationDate = .distantFuture
        return item
    }

    private nonisolated static func itemIdentifier(_ readingID: String) -> String {
        itemIdentifierPrefix + readingID
    }

    func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        guard !items.isEmpty else { return }
        try await withCheckedThrowingContinuation { continuation in
            index.indexSearchableItems(items) { error in
                self.resume(continuation, with: error)
            }
        }
    }

    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await withCheckedThrowingContinuation { continuation in
            index.deleteSearchableItems(withIdentifiers: identifiers) { error in
                self.resume(continuation, with: error)
            }
        }
    }

    func deleteDomain() async throws {
        try await withCheckedThrowingContinuation { continuation in
            index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { error in
                self.resume(continuation, with: error)
            }
        }
    }

    nonisolated func resume(_ continuation: CheckedContinuation<Void, Error>, with error: Error?) {
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

private extension SpotlightVisualIndex {
    func acquireReconciliation() async {
        if !isReconciling {
            isReconciling = true
            return
        }
        await withCheckedContinuation { continuation in
            reconciliationWaiters.append(continuation)
        }
    }

    func releaseReconciliation() {
        if reconciliationWaiters.isEmpty {
            isReconciling = false
        } else {
            reconciliationWaiters.removeFirst().resume()
        }
    }

    func requireCurrentReconciliation(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == latestReconciliationGeneration else {
            throw CancellationError()
        }
    }
}
