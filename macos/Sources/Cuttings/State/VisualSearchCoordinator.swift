// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

private struct VisualSearchSpotlightOutcome: Sendable {
    let indexedCount: Int
    let deletedCount: Int
    let searchStateMayHaveChanged: Bool
    let wasCancelled: Bool

    static let cancelled = VisualSearchSpotlightOutcome(
        indexedCount: 0,
        deletedCount: 0,
        searchStateMayHaveChanged: false,
        wasCancelled: true
    )
}

private enum VisualAnalysisPassOutcome: Sendable {
    case completed
    case failed
    case cancelled

    var wasCancelled: Bool {
        guard case .cancelled = self else { return false }
        return true
    }
}

private struct CandidateCacheKey: Hashable {
    let query: String
    let limit: Int

    init(query: String, limit: Int) {
        self.query = query
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
        self.limit = limit
    }
}

private enum AnalysisOutcome: Sendable {
    case analyzed(VisualAnalysisWorkItem, VisualAnalysisResult)
    case unsupported(VisualAnalysisWorkItem)
    case failed
    case cancelled
}

private extension VisualAssetSnapshot {
    var spotlightAsset: SpotlightVisualAsset {
        SpotlightVisualAsset(
            readingID: readingID,
            assetHash: contentHash,
            assetURL: fileURL,
            displayTitle: title
        )
    }
}

/// Coordinates Apple's local visual services with the disposable Rust cache.
/// Every pass uses core-staged snapshots and core revalidates each completion.
actor VisualSearchCoordinator {
    private let analyzer: any VisualAnalyzing
    private let analyzerVersion: String
    private let spotlight: any SpotlightVisualIndexing
    private let analysisBatchSize: UInt32

    private var candidateGeneration: UInt64 = 0
    private var candidateCache: [CandidateCacheKey: [String]] = [:]
    private var nextReconciliationRequest: UInt64 = 0
    private var reconciliationGeneration: UInt64 = 0
    private var activeAnalysisGenerations: Set<UInt64> = []
    private var analysisCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var unpublishedAnalyzedCount = 0
    private var unpublishedHydratedCount = 0
    private var analysisPublicationToken: UInt64 = 0

    init(
        analyzer: any VisualAnalyzing,
        analyzerVersion: String,
        spotlight: any SpotlightVisualIndexing,
        analysisBatchSize: UInt32 = 16
    ) {
        self.analyzer = analyzer
        self.analyzerVersion = analyzerVersion
        self.spotlight = spotlight
        self.analysisBatchSize = max(1, analysisBatchSize)
    }

    /// Reconcile Spotlight and Vision/colour analysis without blocking app boot.
    /// Spotlight runs alongside the bounded analysis loop; both are local and
    /// independently disposable, so one platform failure does not suppress the
    /// other path.
    func reconcile(core: any VisualSearchCore) async throws -> VisualSearchReconciliation {
        nextReconciliationRequest &+= 1
        let generation = nextReconciliationRequest
        let assets = try await core.currentVisualAssets()
        try Task.checkCancellation()
        guard generation > reconciliationGeneration else { throw CancellationError() }
        reconciliationGeneration = generation
        try ensureCurrentReconciliation(generation)
        let spotlightAssets = assets.map(\.spotlightAsset)

        async let spotlightResult = reconcileSpotlight(spotlightAssets)
        async let analysisResult = reconcileAnalysis(with: core, generation: generation)
        let (spotlightOutcome, analysisOutcome) = await (spotlightResult, analysisResult)
        await waitForEarlierAnalysisPasses(before: generation)
        try ensureCurrentReconciliation(generation)
        guard !spotlightOutcome.wasCancelled,
              !analysisOutcome.wasCancelled else { throw CancellationError() }
        let result = VisualSearchReconciliation(
            analyzedCount: unpublishedAnalyzedCount,
            hydratedAnalysisCount: unpublishedHydratedCount,
            spotlightIndexedCount: spotlightOutcome.indexedCount,
            spotlightDeletedCount: spotlightOutcome.deletedCount,
            analysisPublicationToken: analysisPublicationToken,
            searchStateMayHaveChanged: spotlightOutcome.searchStateMayHaveChanged
        )
        if result.changedSearchResults {
            invalidateCandidateCache()
        }
        return result
    }

    /// Best-first semantic candidates for one complete Rust query. Results are
    /// cached by normalized query, so one board snapshot uses a stable Spotlight
    /// ranking until the donated asset generation changes.
    func candidates(for query: String, limit: Int) async throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = CandidateCacheKey(query: trimmed, limit: limit)
        guard !key.query.isEmpty, limit > 0 else { return [] }
        if let cached = candidateCache[key] {
            return cached
        }

        let generation = candidateGeneration
        let matches = try await spotlight.search(trimmed, limit: limit)
        try Task.checkCancellation()
        guard generation == candidateGeneration else { throw CancellationError() }

        var seen = Set<String>()
        let uniqueMatches = matches.filter { !$0.isEmpty && seen.insert($0).inserted }
        candidateCache[key] = uniqueMatches
        return uniqueMatches
    }

    func invalidateCandidateCache() {
        candidateGeneration &+= 1
        candidateCache.removeAll(keepingCapacity: true)
    }

    func acknowledgeAnalysisPresentation(_ token: UInt64) {
        guard token == analysisPublicationToken else { return }
        unpublishedAnalyzedCount = 0
        unpublishedHydratedCount = 0
    }

    private func reconcileSpotlight(
        _ assets: [SpotlightVisualAsset]
    ) async -> VisualSearchSpotlightOutcome {
        guard !Task.isCancelled else { return .cancelled }
        do {
            let result = try await spotlight.reconcile(assets)
            guard !Task.isCancelled else { return .cancelled }
            return VisualSearchSpotlightOutcome(
                indexedCount: result.indexedCount,
                deletedCount: result.deletedCount,
                searchStateMayHaveChanged: false,
                wasCancelled: false
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            // Spotlight may repair or clear its derived domain before surfacing
            // an error, so counts are unknown but cached candidates are stale.
            return VisualSearchSpotlightOutcome(
                indexedCount: 0,
                deletedCount: 0,
                searchStateMayHaveChanged: true,
                wasCancelled: false
            )
        }
    }

    private func reconcileAnalysis(
        with core: any VisualSearchCore,
        generation: UInt64
    ) async -> VisualAnalysisPassOutcome {
        activeAnalysisGenerations.insert(generation)
        defer { finishAnalysisPass(generation) }
        do {
            try await analyzePendingAssets(with: core, generation: generation)
            return .completed
        } catch is CancellationError {
            return .cancelled
        } catch {
            // Analysis is optional derived work. A core/cache failure should not
            // suppress a Spotlight change completed by the parallel branch.
            return .failed
        }
    }

    private func analyzePendingAssets(
        with core: any VisualSearchCore, generation: UInt64
    ) async throws {
        let pending = try await core.pendingVisualAnalysis(
            analyzerVersion: analyzerVersion,
            limit: .max
        )
        if pending.hydratedCount > 0 {
            unpublishedHydratedCount += pending.hydratedCount
            analysisPublicationToken &+= 1
        }
        try ensureCurrentReconciliation(generation)

        let batchSize = Int(analysisBatchSize)
        for start in stride(from: 0, to: pending.tasks.count, by: batchSize) {
            try ensureCurrentReconciliation(generation)
            let end = min(start + batchSize, pending.tasks.count)
            try await analyze(
                Array(pending.tasks[start ..< end]),
                with: core,
                generation: generation
            )
        }
        try Task.checkCancellation()
    }

    private func analyze(
        _ tasks: [VisualAnalysisWorkItem],
        with core: any VisualSearchCore,
        generation: UInt64
    ) async throws {
        let outcomes = await analysisOutcomes(for: tasks)
        for outcome in outcomes {
            try ensureCurrentReconciliation(generation)
            guard let completion = Self.completion(for: outcome) else { continue }
            do {
                if try await core.completeVisualAnalysis(task: completion.0, result: completion.1) {
                    unpublishedAnalyzedCount += 1
                    analysisPublicationToken &+= 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One transient cache/write failure must not discard accepted
                // completions from the same pass; it remains pending for retry.
                continue
            }
        }
    }

    private func waitForEarlierAnalysisPasses(before generation: UInt64) async {
        while activeAnalysisGenerations.contains(where: { $0 < generation }) {
            await withCheckedContinuation { continuation in
                analysisCompletionWaiters.append(continuation)
            }
        }
    }

    private func finishAnalysisPass(_ generation: UInt64) {
        activeAnalysisGenerations.remove(generation)
        let waiters = analysisCompletionWaiters
        analysisCompletionWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    private func analysisOutcomes(
        for tasks: [VisualAnalysisWorkItem]
    ) async -> [AnalysisOutcome] {
        let analyzer = analyzer
        return await withTaskGroup(of: AnalysisOutcome.self) { group in
            for task in tasks {
                group.addTask {
                    await Self.analyze(task, with: analyzer)
                }
            }

            var values: [AnalysisOutcome] = []
            for await outcome in group {
                values.append(outcome)
            }
            return values
        }
    }

    private static func analyze(
        _ task: VisualAnalysisWorkItem,
        with analyzer: any VisualAnalyzing
    ) async -> AnalysisOutcome {
        guard !Task.isCancelled else { return .cancelled }
        do {
            let result = try await analyzer.analyze(
                imageAt: task.fileURL
            )
            return Task.isCancelled ? .cancelled : .analyzed(task, result)
        } catch is CancellationError {
            return .cancelled
        } catch let error as VisualAnalysisError {
            return error.isPermanentlyUnsupported ? .unsupported(task) : .failed
        } catch {
            return .failed
        }
    }

    private static func completion(
        for outcome: AnalysisOutcome
    ) -> (VisualAnalysisWorkItem, VisualAnalysisCompletion)? {
        switch outcome {
        case let .analyzed(task, result) where result.analyzerVersion == task.analyzerVersion:
            (task, completionResult(result))
        case let .unsupported(task):
            (task, .unsupported)
        case .analyzed, .failed, .cancelled:
            nil
        }
    }

    private static func completionResult(
        _ result: VisualAnalysisResult
    ) -> VisualAnalysisCompletion {
        VisualAnalysisCompletion(
            supported: true,
            labels: result.labels.map {
                VisualAnalysisLabelFact(identifier: $0.identifier, confidence: $0.confidence)
            },
            palette: result.colors.map {
                VisualAnalysisColorFact(
                    red: $0.red,
                    green: $0.green,
                    blue: $0.blue,
                    weight: $0.weight
                )
            }
        )
    }

    private func ensureCurrentReconciliation(_ generation: UInt64) throws {
        guard generation == reconciliationGeneration else { throw CancellationError() }
        try Task.checkCancellation()
    }
}
