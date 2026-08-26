// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum CoordinatorVisualCoreError: Error, Sendable {
    case failed
}

actor CoordinatorFakeVisualCore: VisualSearchCore {
    struct Completion: Equatable, Sendable {
        let task: VisualAnalysisWorkItem
        let result: VisualAnalysisCompletion
    }

    private let tasks: [VisualAnalysisWorkItem]
    private let hydratedCount: Int
    private let failsPendingAnalysis: Bool
    private let failingCompletionReadingIDs: Set<String>
    private var completions: [Completion] = []

    init(
        tasks: [VisualAnalysisWorkItem] = [],
        hydratedCount: Int = 0,
        failsPendingAnalysis: Bool = false,
        failingCompletionReadingIDs: Set<String> = []
    ) {
        self.tasks = tasks
        self.hydratedCount = hydratedCount
        self.failsPendingAnalysis = failsPendingAnalysis
        self.failingCompletionReadingIDs = failingCompletionReadingIDs
    }

    func pendingVisualAnalysis(
        analyzerVersion _: String,
        limit _: UInt32
    ) async throws -> PendingVisualAnalysis {
        if failsPendingAnalysis {
            throw CoordinatorVisualCoreError.failed
        }
        return PendingVisualAnalysis(tasks: tasks, hydratedCount: hydratedCount)
    }

    func completeVisualAnalysis(
        task: VisualAnalysisWorkItem,
        result: VisualAnalysisCompletion
    ) async throws -> Bool {
        if failingCompletionReadingIDs.contains(task.readingID) {
            throw CoordinatorVisualCoreError.failed
        }
        completions.append(Completion(task: task, result: result))
        return true
    }

    func currentVisualAssets() async throws -> [VisualAssetSnapshot] {
        []
    }

    func recordedCompletions() -> [Completion] {
        completions
    }
}

actor CoordinatorFakeAnalyzer: VisualAnalyzing {
    enum Response: Sendable {
        case success(VisualAnalysisResult)
        case permanentlyUnsupported
        case transientFailure
    }

    private let responses: [String: Response]
    private var paths: [String] = []

    init(responses: [String: Response] = [:]) {
        self.responses = responses
    }

    func analyze(imageAt url: URL) async throws -> VisualAnalysisResult {
        paths.append(url.path)
        switch responses[url.path] ?? .transientFailure {
        case let .success(result):
            return result
        case .permanentlyUnsupported:
            throw VisualAnalysisError.unsupportedImage(url)
        case .transientFailure:
            throw VisualAnalysisError.unreadableImage(url)
        }
    }

    func recordedPaths() -> [String] {
        paths
    }
}

enum CoordinatorSpotlightError: Error, Sendable {
    case failed
}

actor CoordinatorFakeSpotlight: SpotlightVisualIndexing {
    struct SearchCall: Equatable, Sendable {
        let query: String
        let limit: Int
    }

    private var searchResults: [String]
    private var failsSearch: Bool
    private var failsReconciliation: Bool
    private var reconciliationResult: SpotlightReconciliationResult
    private var searches: [SearchCall] = []
    private var reconciliations: [[SpotlightVisualAsset]] = []

    init(
        searchResults: [String] = [],
        failsSearch: Bool = false,
        failsReconciliation: Bool = false,
        reconciliationResult: SpotlightReconciliationResult = .unavailable
    ) {
        self.searchResults = searchResults
        self.failsSearch = failsSearch
        self.failsReconciliation = failsReconciliation
        self.reconciliationResult = reconciliationResult
    }

    func reconcile(
        _ assets: [SpotlightVisualAsset]
    ) async throws -> SpotlightReconciliationResult {
        reconciliations.append(assets)
        if failsReconciliation {
            throw CoordinatorSpotlightError.failed
        }
        return reconciliationResult
    }

    func search(_ query: String, limit: Int) async throws -> [String] {
        searches.append(SearchCall(query: query, limit: limit))
        if failsSearch {
            throw CoordinatorSpotlightError.failed
        }
        return searchResults
    }

    func setSearchResults(_ results: [String]) {
        searchResults = results
    }

    func setFailsSearch(_ value: Bool) {
        failsSearch = value
    }

    func setFailsReconciliation(_ value: Bool) {
        failsReconciliation = value
    }

    func recordedSearches() -> [SearchCall] {
        searches
    }

    func reconciliationCount() -> Int {
        reconciliations.count
    }
}

actor CoordinatorGenerationCore: VisualSearchCore {
    struct CallCounts: Equatable, Sendable {
        let assetReads: Int
        let pendingReads: Int
    }

    private var assetReadCount = 0
    private var pendingReadCount = 0
    private var firstAssetReadContinuation: CheckedContinuation<Void, Never>?
    private var firstAssetReadWaiters: [CheckedContinuation<Void, Never>] = []

    func pendingVisualAnalysis(
        analyzerVersion _: String,
        limit _: UInt32
    ) async throws -> PendingVisualAnalysis {
        pendingReadCount += 1
        return PendingVisualAnalysis(tasks: [], hydratedCount: 0)
    }

    func completeVisualAnalysis(
        task _: VisualAnalysisWorkItem,
        result _: VisualAnalysisCompletion
    ) async throws -> Bool {
        false
    }

    func currentVisualAssets() async throws -> [VisualAssetSnapshot] {
        assetReadCount += 1
        guard assetReadCount == 1 else { return [] }

        await withCheckedContinuation { continuation in
            firstAssetReadContinuation = continuation
            let waiters = firstAssetReadWaiters
            firstAssetReadWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        return []
    }

    func waitUntilFirstAssetReadIsSuspended() async {
        guard firstAssetReadContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            firstAssetReadWaiters.append(continuation)
        }
    }

    func resumeFirstAssetRead() {
        let continuation = firstAssetReadContinuation
        firstAssetReadContinuation = nil
        continuation?.resume()
    }

    func recordedCallCounts() -> CallCounts {
        CallCounts(
            assetReads: assetReadCount,
            pendingReads: pendingReadCount
        )
    }
}
