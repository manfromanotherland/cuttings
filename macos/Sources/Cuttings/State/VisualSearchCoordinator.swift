// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct VisualSearchReconciliation: Equatable, Sendable {
    let analyzedCount: Int
    let spotlightIndexedCount: Int
    let spotlightDeletedCount: Int
    private let searchStateMayHaveChanged: Bool

    init(
        analyzedCount: Int,
        spotlightIndexedCount: Int,
        spotlightDeletedCount: Int,
        searchStateMayHaveChanged: Bool = false
    ) {
        self.analyzedCount = analyzedCount
        self.spotlightIndexedCount = spotlightIndexedCount
        self.spotlightDeletedCount = spotlightDeletedCount
        self.searchStateMayHaveChanged = searchStateMayHaveChanged
    }

    var changedSearchResults: Bool {
        searchStateMayHaveChanged
            || analyzedCount > 0
            || spotlightIndexedCount > 0
            || spotlightDeletedCount > 0
    }
}

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
    case completed(Int)
    case failed
    case cancelled

    var completedCount: Int {
        guard case let .completed(count) = self else { return 0 }
        return count
    }

    var wasCancelled: Bool {
        guard case .cancelled = self else { return false }
        return true
    }
}

/// Joins the disposable Rust visual-analysis cache to Apple's local platform
/// services. It owns no library truth: every pass starts from assets the core
/// has copied into immutable, content-addressed snapshots, and every completion
/// is revalidated against the live library by core.
actor VisualSearchCoordinator {
    private struct CandidateCacheKey: Hashable {
        let query: String
        let limit: Int
    }

    private enum AnalysisOutcome: Sendable {
        case analyzed(VisualAnalysisWorkItem, VisualAnalysisResult)
        case unsupported(VisualAnalysisWorkItem)
        case failed
        case cancelled
    }

    private let analyzer: any VisualAnalyzing
    private let analyzerVersion: String
    private let spotlight: any SpotlightVisualIndexing
    private let analysisBatchSize: UInt32

    private var candidateGeneration: UInt64 = 0
    private var candidateCache: [CandidateCacheKey: [String]] = [:]
    private var reconciliationGeneration: UInt64 = 0

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
        reconciliationGeneration &+= 1
        let generation = reconciliationGeneration
        let assets = try await core.currentVisualAssets()
        try ensureCurrentReconciliation(generation)
        let spotlightAssets = assets.map {
            SpotlightVisualAsset(
                readingID: $0.readingID,
                assetHash: $0.contentHash,
                assetURL: $0.fileURL,
                displayTitle: $0.title
            )
        }

        async let spotlightResult = reconcileSpotlight(spotlightAssets)
        async let analysisResult = reconcileAnalysis(with: core, generation: generation)
        let (spotlightOutcome, analysisOutcome) = await (spotlightResult, analysisResult)
        try ensureCurrentReconciliation(generation)
        guard !spotlightOutcome.wasCancelled,
              !analysisOutcome.wasCancelled else { throw CancellationError() }
        let result = VisualSearchReconciliation(
            analyzedCount: analysisOutcome.completedCount,
            spotlightIndexedCount: spotlightOutcome.indexedCount,
            spotlightDeletedCount: spotlightOutcome.deletedCount,
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
        let key = CandidateCacheKey(query: Self.normalizedQuery(trimmed), limit: limit)
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
        do {
            return try await .completed(analyzePendingAssets(with: core, generation: generation))
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
    ) async throws -> Int {
        let tasks = try await core.pendingVisualAnalysis(
            analyzerVersion: analyzerVersion,
            limit: .max
        )
        try ensureCurrentReconciliation(generation)

        var total = 0
        let batchSize = Int(analysisBatchSize)
        for start in stride(from: 0, to: tasks.count, by: batchSize) {
            try ensureCurrentReconciliation(generation)
            let end = min(start + batchSize, tasks.count)
            total += try await analyze(
                Array(tasks[start ..< end]),
                with: core,
                generation: generation
            )
        }
        try Task.checkCancellation()
        return total
    }

    private func analyze(
        _ tasks: [VisualAnalysisWorkItem],
        with core: any VisualSearchCore,
        generation: UInt64
    ) async throws -> Int {
        let outcomes = await analysisOutcomes(for: tasks)
        var accepted = 0
        for outcome in outcomes {
            try ensureCurrentReconciliation(generation)
            guard let completion = Self.completion(for: outcome) else { continue }
            do {
                if try await core.completeVisualAnalysis(task: completion.0, result: completion.1) {
                    accepted += 1
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One transient cache/write failure must not discard accepted
                // completions from the same pass; it remains pending for retry.
                continue
            }
        }
        return accepted
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

    private static func normalizedQuery(_ query: String) -> String {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}
