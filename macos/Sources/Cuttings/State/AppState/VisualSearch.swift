// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Derived visual search ────────────────────────────────────────────────────
// Background Vision/colour analysis and Core Spotlight donation. Neither path
// delays boot or mutates the Markdown library; Rust revalidates every result.

extension AppState {
    func cancelVisualSearchReconciliation() -> Task<Void, Never>? {
        visualSearchRerunPending = false
        visualSearchTask?.cancel()
        return visualSearchTask
    }

    func scheduleVisualSearchReconciliation() {
        visualSearchRerunPending = true
        guard visualSearchTask == nil,
              let core,
              let visualSearchCoordinator,
              let coreID = activeCoreID else { return }
        let session = librarySessionGeneration

        visualSearchTask = Task(priority: .utility) { [weak self] in
            await self?.runVisualSearchReconciliations(
                core: core,
                coordinator: visualSearchCoordinator,
                coreID: coreID,
                session: session
            )
        }
    }

    private func runVisualSearchReconciliations(
        core: any CoreBridging,
        coordinator: VisualSearchCoordinator,
        coreID: ObjectIdentifier,
        session: UInt64
    ) async {
        repeat {
            guard isCurrentVisualSearchSession(coreID: coreID, session: session) else { break }
            visualSearchRerunPending = false
            do {
                let result = try await coordinator.reconcile(core: core)
                guard !Task.isCancelled else { break }
                guard isCurrentVisualSearchSession(coreID: coreID, session: session) else { break }
                await visualSearchDidFinish(result)
            } catch is CancellationError {
                // Replacing a library deliberately supersedes this work.
                break
            } catch {
                // Visual indexing is an optional, rebuildable enhancement. A
                // corrupt image or unavailable system index must never make the
                // local library unusable or raise a blocking app alert.
            }
        } while visualSearchRerunPending && !Task.isCancelled

        visualSearchTask = nil
        if visualSearchRerunPending {
            scheduleVisualSearchReconciliation()
        }
    }

    private func isCurrentVisualSearchSession(
        coreID: ObjectIdentifier,
        session: UInt64
    ) -> Bool {
        !Task.isCancelled
            && session == librarySessionGeneration
            && coreID == activeCoreID
    }

    private func visualSearchDidFinish(_ result: VisualSearchReconciliation) async {
        guard result.shouldReloadReadings(
            hasActiveSearch: activeVisualSearchQuery != nil
        ) else { return }
        let loadResult = await loadReadings(resetSelectionIfMissing: false)
        guard loadResult == .published else { return }
        await visualSearchCoordinator?.acknowledgeAnalysisPresentation(
            result.analysisPublicationToken
        )
    }

    private var activeVisualSearchQuery: String? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }
}
