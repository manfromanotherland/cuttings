// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Incremental sync (FSEvents) ─────────────────────────────────────────────

extension AppState {
    private func requestWatcherSync(session: UInt64) {
        guard session == librarySessionGeneration else { return }
        watcherSyncPending = true
        scheduleWatcherSyncIfNeeded(session: session)
    }

    func scheduleWatcherSyncIfNeeded(session: UInt64) {
        guard session == librarySessionGeneration,
              !isReconcilingLibrary,
              watcherSyncPending,
              watcherSyncTask == nil,
              let bridge = core as? CoreBridge,
              activeCoreID == ObjectIdentifier(bridge) else { return }

        watcherSyncPending = false
        watcherSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.sync(using: bridge, session: session)
            self.finishWatcherSync(session: session)
        }
    }

    private func finishWatcherSync(session: UInt64) {
        guard session == librarySessionGeneration else { return }
        watcherSyncTask = nil
        scheduleWatcherSyncIfNeeded(session: session)
    }

    private func sync(using bridge: CoreBridge, session: UInt64) async {
        guard session == librarySessionGeneration,
              activeCoreID == ObjectIdentifier(bridge),
              !Task.isCancelled else { return }
        let bridgeID = ObjectIdentifier(bridge)
        do {
            let changed = try await bridge.sync()
            guard session == librarySessionGeneration,
                  activeCoreID == bridgeID,
                  !Task.isCancelled else { return }
            if changed > 0 {
                await refresh()
                scheduleVisualSearchReconciliation()
            }
        } catch {
            if session == librarySessionGeneration,
               activeCoreID == bridgeID,
               !Task.isCancelled {
                self.error = error.localizedDescription
            }
        }
    }

    func startWatcher(libraryPath: String, session: UInt64) {
        guard session == librarySessionGeneration else { return }
        // Tear down the previous watcher before replacing it. Reassigning alone
        // would leak it — the FSEvents stream keeps it alive, still watching the
        // old folder and firing sync() against the new library. invalidate()
        // runs while we still hold the strong reference, so the release it
        // triggers can't deallocate the watcher mid-teardown.
        watcher?.invalidate()
        watcher = FolderWatcher(libraryPath: libraryPath) { [weak self] in
            Task { @MainActor [weak self] in
                self?.requestWatcherSync(session: session)
            }
        }
    }

    func startRebuildRetryWatcher(
        libraryURL: URL,
        session: UInt64,
        retryImmediately: Bool
    ) {
        guard session == librarySessionGeneration else { return }
        watcher?.invalidate()
        watcher = FolderWatcher(libraryPath: libraryURL.path) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.retryFullRebuildWhenReady(
                    libraryURL: libraryURL,
                    session: session,
                    allowsImmediateRecoveryRetry: true
                )
            }
        }
        guard retryImmediately else { return }
        Task { @MainActor [weak self] in
            await self?.retryFullRebuildWhenReady(
                libraryURL: libraryURL,
                session: session,
                allowsImmediateRecoveryRetry: false
            )
        }
    }

    private func retryFullRebuildWhenReady(
        libraryURL: URL,
        session: UInt64,
        allowsImmediateRecoveryRetry: Bool
    ) async {
        while session == librarySessionGeneration,
              activeLibraryWriteCount > 0 || isSaving {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard session == librarySessionGeneration, canChangeLibrary else { return }
        await boot(
            url: libraryURL,
            allowsImmediateRecoveryRetry: allowsImmediateRecoveryRetry
        )
    }
}
