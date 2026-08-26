// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

final class VisualSearchPublicationTests: XCTestCase {
    func testPendingAnalysisMapperPreservesTasksAndHydrationCount() {
        let ffiTask = FfiVisualAnalysisTask(
            readingId: "reading",
            relativePath: "assets/image.jpg",
            absoluteFilePath: "/tmp/cuttings-visual-tests/image.jpg",
            contentHash: "hash-reading",
            analyzerVersion: "vision-2"
        )

        let pending = PendingVisualAnalysis(FfiPendingVisualAnalysis(
            tasks: [ffiTask],
            hydratedCount: 7
        ))

        XCTAssertEqual(pending.hydratedCount, 7)
        XCTAssertEqual(pending.tasks, [VisualAnalysisWorkItem(ffiTask)])
    }

    func testCachedAnalysisHydrationRefreshesCardsWithoutRunningAnalyzer() async throws {
        let analyzer = CoordinatorFakeAnalyzer()
        let coordinator = makeCoordinator(analyzer: analyzer)
        let core = CoordinatorFakeVisualCore(hydratedCount: 1)

        let reconciliation = try await coordinator.reconcile(core: core)

        XCTAssertEqual(reconciliation.analyzedCount, 0)
        XCTAssertEqual(reconciliation.hydratedAnalysisCount, 1)
        XCTAssertTrue(reconciliation.changedCardPresentation)
        XCTAssertTrue(reconciliation.changedSearchResults)
        XCTAssertTrue(reconciliation.shouldReloadReadings(hasActiveSearch: false))
        let analyzedPaths = await analyzer.recordedPaths()
        XCTAssertTrue(analyzedPaths.isEmpty)
    }

    func testReadingReloadPolicyKeepsSpotlightChangesScopedToActiveSearch() {
        let spotlightOnly = VisualSearchReconciliation(
            analyzedCount: 0,
            spotlightIndexedCount: 1,
            spotlightDeletedCount: 0
        )

        XCTAssertFalse(spotlightOnly.shouldReloadReadings(hasActiveSearch: false))
        XCTAssertTrue(spotlightOnly.shouldReloadReadings(hasActiveSearch: true))
    }

    func testSupersededHydrationIsPublishedByTheWinningReconciliation() async throws {
        let core = CoordinatorHydrationRaceCore()
        let coordinator = makeCoordinator()

        let older = Task {
            try await coordinator.reconcile(core: core)
        }
        await core.waitUntilFirstPendingReadIsSuspended()
        let newer = Task {
            try await coordinator.reconcile(core: core)
        }
        await core.waitUntilSecondPendingRead()
        await core.resumeFirstPendingRead()

        let published = try await newer.value
        XCTAssertEqual(published.analyzedCount, 0)
        XCTAssertEqual(published.hydratedAnalysisCount, 1)
        XCTAssertTrue(published.changedCardPresentation)

        do {
            _ = try await older.value
            XCTFail("The superseded reconciliation should be cancelled")
        } catch is CancellationError {
            // Expected: its mutation is carried by the winning pass.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let repeated = try await coordinator.reconcile(core: core)
        XCTAssertEqual(repeated.hydratedAnalysisCount, 1)
        XCTAssertEqual(repeated.analysisPublicationToken, published.analysisPublicationToken)

        await coordinator.acknowledgeAnalysisPresentation(repeated.analysisPublicationToken)
        let settled = try await coordinator.reconcile(core: core)
        XCTAssertEqual(settled.hydratedAnalysisCount, 0)
        XCTAssertFalse(settled.changedCardPresentation)
    }

    func testFailedNewerPreflightDoesNotStrandOlderHydration() async throws {
        let core = CoordinatorHydrationRaceCore(failsSecondAssetRead: true)
        let coordinator = makeCoordinator()

        let older = Task {
            try await coordinator.reconcile(core: core)
        }
        await core.waitUntilFirstPendingReadIsSuspended()

        do {
            _ = try await coordinator.reconcile(core: core)
            XCTFail("The newer asset preflight should fail")
        } catch is CoordinatorVisualCoreError {
            // Expected: a failed preflight never supersedes viable work.
        } catch {
            XCTFail("Expected CoordinatorVisualCoreError, got \(error)")
        }

        await core.resumeFirstPendingRead()
        let published = try await older.value
        XCTAssertEqual(published.hydratedAnalysisCount, 1)
        XCTAssertTrue(published.changedCardPresentation)
    }

    func testStaleAcknowledgementCannotClearNewerAnalysisChange() async throws {
        let core = CoordinatorQueuedHydrationCore(hydratedCounts: [1, 1, 0, 0])
        let coordinator = makeCoordinator()

        let first = try await coordinator.reconcile(core: core)
        let second = try await coordinator.reconcile(core: core)

        XCTAssertNotEqual(first.analysisPublicationToken, second.analysisPublicationToken)
        XCTAssertEqual(second.hydratedAnalysisCount, 2)

        await coordinator.acknowledgeAnalysisPresentation(first.analysisPublicationToken)
        let stillPending = try await coordinator.reconcile(core: core)
        XCTAssertEqual(stillPending.hydratedAnalysisCount, 2)
        XCTAssertEqual(stillPending.analysisPublicationToken, second.analysisPublicationToken)

        await coordinator.acknowledgeAnalysisPresentation(stillPending.analysisPublicationToken)
        let settled = try await coordinator.reconcile(core: core)
        XCTAssertEqual(settled.hydratedAnalysisCount, 0)
        XCTAssertFalse(settled.changedCardPresentation)
    }

    func testAcceptedSupersededCompletionIsPublishedByWinningReconciliation() async throws {
        let (core, coordinator) = makeCompletionRace()

        let older = Task {
            try await coordinator.reconcile(core: core)
        }
        await core.waitUntilCompletionIsSuspended()

        let newer = Task {
            try await coordinator.reconcile(core: core)
        }
        await core.waitUntilSecondPendingRead()
        await core.resumeCompletion()

        let published = try await newer.value
        XCTAssertEqual(published.analyzedCount, 1)
        XCTAssertTrue(published.changedCardPresentation)

        do {
            _ = try await older.value
            XCTFail("The superseded reconciliation should be cancelled")
        } catch is CancellationError {
            // Expected: its accepted completion is carried by the winning pass.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    private func makeCompletionRace() -> (
        CoordinatorCompletionRaceCore,
        VisualSearchCoordinator
    ) {
        let task = VisualAnalysisWorkItem(
            readingID: "accepted",
            relativePath: "assets/accepted.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/cuttings-visual-tests/accepted.jpg"),
            contentHash: "hash-accepted",
            analyzerVersion: "vision-2"
        )
        let analysis = VisualAnalysisResult(
            analyzerVersion: "vision-2",
            labels: [],
            colors: [VisualColorCluster(red: 0.2, green: 0.4, blue: 0.6, weight: 1)]
        )
        let analyzer = CoordinatorFakeAnalyzer(
            responses: [task.fileURL.path: .success(analysis)]
        )
        return (
            CoordinatorCompletionRaceCore(task: task),
            makeCoordinator(analyzer: analyzer)
        )
    }

    private func makeCoordinator(
        analyzer: any VisualAnalyzing = CoordinatorFakeAnalyzer()
    ) -> VisualSearchCoordinator {
        VisualSearchCoordinator(
            analyzer: analyzer,
            analyzerVersion: "vision-2",
            spotlight: CoordinatorFakeSpotlight(),
            analysisBatchSize: 2
        )
    }
}
