// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

actor CoordinatorHydrationRaceCore: VisualSearchCore {
    private let failsSecondAssetRead: Bool
    private var assetReadCount = 0
    private var pendingReadCount = 0
    private var firstPendingContinuation: CheckedContinuation<Void, Never>?
    private var firstPendingWaiters: [CheckedContinuation<Void, Never>] = []
    private var secondPendingWaiters: [CheckedContinuation<Void, Never>] = []

    init(failsSecondAssetRead: Bool = false) {
        self.failsSecondAssetRead = failsSecondAssetRead
    }

    func pendingVisualAnalysis(
        analyzerVersion _: String,
        limit _: UInt32
    ) async throws -> PendingVisualAnalysis {
        pendingReadCount += 1
        if pendingReadCount == 1 {
            await withCheckedContinuation { continuation in
                firstPendingContinuation = continuation
                let waiters = firstPendingWaiters
                firstPendingWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            return PendingVisualAnalysis(tasks: [], hydratedCount: 1)
        }

        let waiters = secondPendingWaiters
        secondPendingWaiters.removeAll()
        waiters.forEach { $0.resume() }
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
        if failsSecondAssetRead, assetReadCount == 2 {
            throw CoordinatorVisualCoreError.failed
        }
        return []
    }

    func waitUntilFirstPendingReadIsSuspended() async {
        guard firstPendingContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            firstPendingWaiters.append(continuation)
        }
    }

    func waitUntilSecondPendingRead() async {
        guard pendingReadCount < 2 else { return }
        await withCheckedContinuation { continuation in
            secondPendingWaiters.append(continuation)
        }
    }

    func resumeFirstPendingRead() {
        let continuation = firstPendingContinuation
        firstPendingContinuation = nil
        continuation?.resume()
    }
}

actor CoordinatorQueuedHydrationCore: VisualSearchCore {
    private var hydratedCounts: [Int]

    init(hydratedCounts: [Int]) {
        self.hydratedCounts = hydratedCounts
    }

    func pendingVisualAnalysis(
        analyzerVersion _: String,
        limit _: UInt32
    ) async throws -> PendingVisualAnalysis {
        let count = hydratedCounts.isEmpty ? 0 : hydratedCounts.removeFirst()
        return PendingVisualAnalysis(tasks: [], hydratedCount: count)
    }

    func completeVisualAnalysis(
        task _: VisualAnalysisWorkItem,
        result _: VisualAnalysisCompletion
    ) async throws -> Bool {
        false
    }

    func currentVisualAssets() async throws -> [VisualAssetSnapshot] {
        []
    }
}

actor CoordinatorCompletionRaceCore: VisualSearchCore {
    private let task: VisualAnalysisWorkItem
    private var pendingReadCount = 0
    private var completionContinuation: CheckedContinuation<Void, Never>?
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []
    private var secondPendingWaiters: [CheckedContinuation<Void, Never>] = []

    init(task: VisualAnalysisWorkItem) {
        self.task = task
    }

    func pendingVisualAnalysis(
        analyzerVersion _: String,
        limit _: UInt32
    ) async throws -> PendingVisualAnalysis {
        pendingReadCount += 1
        if pendingReadCount == 1 {
            return PendingVisualAnalysis(tasks: [task], hydratedCount: 0)
        }
        let waiters = secondPendingWaiters
        secondPendingWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return PendingVisualAnalysis(tasks: [], hydratedCount: 0)
    }

    func completeVisualAnalysis(
        task _: VisualAnalysisWorkItem,
        result _: VisualAnalysisCompletion
    ) async throws -> Bool {
        await withCheckedContinuation { continuation in
            completionContinuation = continuation
            let waiters = completionWaiters
            completionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        return true
    }

    func currentVisualAssets() async throws -> [VisualAssetSnapshot] {
        []
    }

    func waitUntilCompletionIsSuspended() async {
        guard completionContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append(continuation)
        }
    }

    func waitUntilSecondPendingRead() async {
        guard pendingReadCount < 2 else { return }
        await withCheckedContinuation { continuation in
            secondPendingWaiters.append(continuation)
        }
    }

    func resumeCompletion() {
        let continuation = completionContinuation
        completionContinuation = nil
        continuation?.resume()
    }
}
