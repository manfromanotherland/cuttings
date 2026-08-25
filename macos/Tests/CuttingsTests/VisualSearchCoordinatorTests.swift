// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

final class VisualSearchCoordinatorTests: XCTestCase {
    func testCandidatesReuseNormalizedQueryAndPreserveDeduplicatedRankOrder() async throws {
        let spotlight = CoordinatorFakeSpotlight(
            searchResults: ["reading-b", "", "reading-a", "reading-b", "reading-c", "reading-a"]
        )
        let coordinator = makeCoordinator(spotlight: spotlight)

        let first = try await coordinator.candidates(for: "  Blue   Chair  ", limit: 20)
        let equivalent = try await coordinator.candidates(for: "blue chair", limit: 20)

        XCTAssertEqual(first, ["reading-b", "reading-a", "reading-c"])
        XCTAssertEqual(equivalent, first)
        let calls = await spotlight.recordedSearches()
        XCTAssertEqual(calls, [.init(query: "Blue   Chair", limit: 20)])
    }

    func testCandidateCacheInvalidationRunsANewSpotlightQuery() async throws {
        let spotlight = CoordinatorFakeSpotlight(searchResults: ["before"])
        let coordinator = makeCoordinator(spotlight: spotlight)

        let before = try await coordinator.candidates(for: "chair", limit: 8)
        XCTAssertEqual(before, ["before"])
        await coordinator.invalidateCandidateCache()
        await spotlight.setSearchResults(["after"])
        let after = try await coordinator.candidates(for: "chair", limit: 8)
        XCTAssertEqual(after, ["after"])

        let calls = await spotlight.recordedSearches()
        XCTAssertEqual(
            calls,
            [
                .init(query: "chair", limit: 8),
                .init(query: "chair", limit: 8)
            ]
        )
    }

    func testFailedCandidateLookupIsNotCached() async throws {
        let spotlight = CoordinatorFakeSpotlight(searchResults: ["chair"], failsSearch: true)
        let coordinator = makeCoordinator(spotlight: spotlight)

        do {
            _ = try await coordinator.candidates(for: "chair", limit: 8)
            XCTFail("A failed Spotlight lookup should be surfaced")
        } catch is CoordinatorSpotlightError {
            // Expected: AppState can choose its Rust-only fallback for this load.
        }

        await spotlight.setFailsSearch(false)
        let retry = try await coordinator.candidates(for: "chair", limit: 8)

        XCTAssertEqual(retry, ["chair"])
        let calls = await spotlight.recordedSearches()
        XCTAssertEqual(calls.count, 2)
    }

    func testSpotlightChangeInvalidatesCandidatesWhenAnalysisLookupFails() async throws {
        let spotlight = CoordinatorFakeSpotlight(
            searchResults: ["before"],
            reconciliationResult: SpotlightReconciliationResult(
                isAvailable: true,
                indexedCount: 1,
                deletedCount: 0,
                unchangedCount: 0
            )
        )
        let coordinator = makeCoordinator(spotlight: spotlight)
        let core = CoordinatorFakeVisualCore(failsPendingAnalysis: true)

        let before = try await coordinator.candidates(for: "chair", limit: 8)
        XCTAssertEqual(before, ["before"])
        await spotlight.setSearchResults(["after"])
        let reconciliation = try await coordinator.reconcile(core: core)
        let refreshed = try await coordinator.candidates(for: "chair", limit: 8)

        XCTAssertTrue(reconciliation.changedSearchResults)
        XCTAssertEqual(reconciliation.analyzedCount, 0)
        XCTAssertEqual(reconciliation.spotlightIndexedCount, 1)
        XCTAssertEqual(refreshed, ["after"])
        let calls = await spotlight.recordedSearches()
        XCTAssertEqual(calls.count, 2)
    }

    func testSpotlightFailureConservativelyInvalidatesCandidateCache() async throws {
        let spotlight = CoordinatorFakeSpotlight(
            searchResults: ["before"],
            failsReconciliation: true
        )
        let coordinator = makeCoordinator(spotlight: spotlight)

        let before = try await coordinator.candidates(for: "chair", limit: 8)
        XCTAssertEqual(before, ["before"])
        await spotlight.setSearchResults(["after"])
        let reconciliation = try await coordinator.reconcile(core: CoordinatorFakeVisualCore())
        let refreshed = try await coordinator.candidates(for: "chair", limit: 8)

        XCTAssertTrue(reconciliation.changedSearchResults)
        XCTAssertEqual(reconciliation.spotlightIndexedCount, 0)
        XCTAssertEqual(reconciliation.spotlightDeletedCount, 0)
        XCTAssertEqual(refreshed, ["after"])
        let calls = await spotlight.recordedSearches()
        XCTAssertEqual(calls.count, 2)
    }

    func testSuccessfulAnalysisMapsLabelsAndPaletteIntoCoreCompletion() async throws {
        let task = makeTask(readingID: "chair", filename: "chair.jpg", analyzerVersion: "vision-2")
        let analysis = VisualAnalysisResult(
            analyzerVersion: "vision-2",
            labels: [
                VisualLabel(identifier: "chair", confidence: 0.91),
                VisualLabel(identifier: "dining_room", confidence: 0.72)
            ],
            colors: [
                VisualColorCluster(red: 0.1, green: 0.2, blue: 0.8, weight: 0.7),
                VisualColorCluster(red: 0.9, green: 0.8, blue: 0.3, weight: 0.3)
            ]
        )
        let core = CoordinatorFakeVisualCore(tasks: [task])
        let analyzer = CoordinatorFakeAnalyzer(responses: [task.fileURL.path: .success(analysis)])
        let coordinator = makeCoordinator(spotlight: CoordinatorFakeSpotlight(), analyzer: analyzer)

        let reconciliation = try await coordinator.reconcile(core: core)

        XCTAssertEqual(reconciliation.analyzedCount, 1)
        let completions = await core.recordedCompletions()
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.task, task)
        XCTAssertTrue(completions.first?.result.supported == true)
        XCTAssertEqual(completions.first?.result.labels, analysis.labels.map {
            VisualAnalysisLabelFact(identifier: $0.identifier, confidence: $0.confidence)
        })
        XCTAssertEqual(completions.first?.result.palette, analysis.colors.map {
            VisualAnalysisColorFact(red: $0.red, green: $0.green, blue: $0.blue, weight: $0.weight)
        })
        let analyzedPaths = await analyzer.recordedPaths()
        XCTAssertEqual(analyzedPaths, [task.fileURL.path])
    }

    func testCompletionFailureDoesNotDiscardAnotherAcceptedAnalysis() async throws {
        let accepted = makeTask(
            readingID: "accepted", filename: "accepted.jpg", analyzerVersion: "vision-2"
        )
        let failed = makeTask(
            readingID: "failed", filename: "failed.jpg", analyzerVersion: "vision-2"
        )
        let result = VisualAnalysisResult(
            analyzerVersion: "vision-2",
            labels: [VisualLabel(identifier: "chair", confidence: 0.91)],
            colors: []
        )
        let core = CoordinatorFakeVisualCore(
            tasks: [accepted, failed],
            failingCompletionReadingIDs: [failed.readingID]
        )
        let analyzer = CoordinatorFakeAnalyzer(
            responses: [
                accepted.fileURL.path: .success(result),
                failed.fileURL.path: .success(result)
            ]
        )
        let coordinator = makeCoordinator(
            spotlight: CoordinatorFakeSpotlight(),
            analyzer: analyzer
        )

        let reconciliation = try await coordinator.reconcile(core: core)

        XCTAssertEqual(reconciliation.analyzedCount, 1)
        XCTAssertTrue(reconciliation.changedSearchResults)
        let completions = await core.recordedCompletions()
        XCTAssertEqual(completions.map(\.task.readingID), [accepted.readingID])
    }

    func testPermanentUnsupportedResultIsCachedButTransientFailureIsRetried() async throws {
        let unsupported = makeTask(
            readingID: "unsupported", filename: "unsupported.bin", analyzerVersion: "vision-2"
        )
        let transient = makeTask(
            readingID: "transient", filename: "temporarily-unreadable.jpg", analyzerVersion: "vision-2"
        )
        let core = CoordinatorFakeVisualCore(tasks: [unsupported, transient])
        let analyzer = CoordinatorFakeAnalyzer(
            responses: [
                unsupported.fileURL.path: .permanentlyUnsupported,
                transient.fileURL.path: .transientFailure
            ]
        )
        let coordinator = makeCoordinator(spotlight: CoordinatorFakeSpotlight(), analyzer: analyzer)

        let reconciliation = try await coordinator.reconcile(core: core)

        XCTAssertEqual(reconciliation.analyzedCount, 1)
        let completions = await core.recordedCompletions()
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.task, unsupported)
        XCTAssertEqual(
            completions.first?.result,
            .unsupported
        )
        let analyzedPaths = await analyzer.recordedPaths()
        XCTAssertEqual(
            Set(analyzedPaths),
            Set([unsupported.fileURL.path, transient.fileURL.path])
        )
    }

    func testNewerReconciliationPreventsOlderPassFromPublishing() async throws {
        let core = CoordinatorGenerationCore()
        let spotlight = CoordinatorFakeSpotlight()
        let coordinator = makeCoordinator(spotlight: spotlight)

        let older = Task {
            try await coordinator.reconcile(core: core)
        }
        await core.waitUntilFirstAssetReadIsSuspended()

        let newer = try await coordinator.reconcile(core: core)
        XCTAssertEqual(newer, VisualSearchReconciliation(
            analyzedCount: 0,
            spotlightIndexedCount: 0,
            spotlightDeletedCount: 0
        ))

        await core.resumeFirstAssetRead()
        do {
            _ = try await older.value
            XCTFail("The superseded reconciliation should be cancelled")
        } catch is CancellationError {
            // Expected: the older generation stops before publishing work.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let coreCounts = await core.recordedCallCounts()
        XCTAssertEqual(coreCounts.assetReads, 2)
        XCTAssertEqual(coreCounts.pendingReads, 1)
        let spotlightReconciliations = await spotlight.reconciliationCount()
        XCTAssertEqual(spotlightReconciliations, 1)
    }

    private func makeCoordinator(
        spotlight: CoordinatorFakeSpotlight,
        analyzer: any VisualAnalyzing = CoordinatorFakeAnalyzer()
    ) -> VisualSearchCoordinator {
        VisualSearchCoordinator(
            analyzer: analyzer,
            analyzerVersion: "vision-2",
            spotlight: spotlight,
            analysisBatchSize: 2
        )
    }

    private func makeTask(
        readingID: String,
        filename: String,
        analyzerVersion: String
    ) -> VisualAnalysisWorkItem {
        VisualAnalysisWorkItem(
            readingID: readingID,
            relativePath: "assets/\(filename)",
            fileURL: URL(fileURLWithPath: "/tmp/cuttings-visual-tests/\(filename)"),
            contentHash: "hash-\(readingID)",
            analyzerVersion: analyzerVersion
        )
    }
}
