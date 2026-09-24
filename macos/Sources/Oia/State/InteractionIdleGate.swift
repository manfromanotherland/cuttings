// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Defers optional derived work between bounded batches while any board scrolls.
/// Main-actor ownership preserves the order of UI phase transitions without
/// publishing app-wide observation changes. Waiting suspends background callers.
@MainActor
final class InteractionIdleGate {
    static let shared = InteractionIdleGate()

    private let idleGrace: Duration
    private var scrollingSources: Set<UUID> = []
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var idleTask: Task<Void, Never>?
    private var idleGeneration: UInt64 = 0

    init(idleGrace: Duration = .milliseconds(180)) {
        self.idleGrace = max(.zero, idleGrace)
    }

    func setScrolling(_ isScrolling: Bool, sourceID: UUID) {
        if isScrolling {
            guard scrollingSources.insert(sourceID).inserted else { return }
            idleGeneration &+= 1
            idleTask?.cancel()
            idleTask = nil
        } else {
            guard scrollingSources.remove(sourceID) != nil,
                  scrollingSources.isEmpty else { return }
            let generation = idleGeneration
            idleTask = Task { [weak self, idleGrace] in
                do {
                    try await Task.sleep(for: idleGrace)
                } catch {
                    return
                }
                self?.resumeWaiters(ifCurrent: generation)
            }
        }
    }

    func waitUntilIdle() async throws {
        try Task.checkCancellation()
        while !scrollingSources.isEmpty || idleTask != nil {
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    waiters[id] = continuation
                }
            } onCancel: {
                Task { @MainActor in self.cancelWaiter(id) }
            }
            try Task.checkCancellation()
        }
    }

    private func resumeWaiters(ifCurrent generation: UInt64) {
        guard generation == idleGeneration, scrollingSources.isEmpty else { return }
        idleTask = nil
        let pending = waiters.values
        waiters.removeAll(keepingCapacity: true)
        for continuation in pending {
            continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
