// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Derived visual search ────────────────────────────────────────────────────
// Background Vision/colour analysis and Core Spotlight donation. Neither path
// delays boot or mutates the Markdown library; Rust revalidates every result.

extension AppState {
    func scheduleVisualSearchReconciliation() {
        visualSearchTask?.cancel()
        guard let core, let visualSearchCoordinator else { return }

        visualSearchTask = Task(priority: .utility) { [weak self] in
            do {
                let result = try await visualSearchCoordinator.reconcile(core: core)
                guard !Task.isCancelled else { return }
                await self?.visualSearchDidFinish(result)
            } catch is CancellationError {
                // Replacing a library or receiving a newer filesystem pass
                // deliberately supersedes this work.
            } catch {
                // Visual indexing is an optional, rebuildable enhancement. A
                // corrupt image or unavailable system index must never make the
                // local library unusable or raise a blocking app alert.
            }
        }
    }

    private func visualSearchDidFinish(_ result: VisualSearchReconciliation) async {
        guard result.changedSearchResults, activeVisualSearchQuery != nil else { return }
        await loadReadings(resetSelectionIfMissing: false)
    }

    private var activeVisualSearchQuery: String? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }
}
