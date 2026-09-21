// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Bounds CPU/GPU-heavy analysis and always performs it in a detached utility
/// task. Cancellation removes queued callers immediately instead of allowing a
/// large library scan to leave a long tail of abandoned work.
actor VisualAnalysisExecutor {
    private let limit: Int
    private var activeCount = 0
    private var nextWaiterID = 0
    private var waiters: [Int: CheckedContinuation<Bool, Never>] = [:]
    private var waiterOrder: [Int] = []
    private var waiterHead = 0

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func run<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        guard await acquire() else { throw CancellationError() }
        defer { release() }

        try Task.checkCancellation()
        return try await Task.detached(priority: .utility, operation: operation).value
    }

    private func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if activeCount < limit {
            activeCount += 1
            return true
        }

        let id = nextWaiterID
        nextWaiterID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters[id] = continuation
                waiterOrder.append(id)
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func release() {
        while waiterHead < waiterOrder.count {
            let id = waiterOrder[waiterHead]
            waiterHead += 1
            guard let continuation = waiters.removeValue(forKey: id) else { continue }
            continuation.resume(returning: true)
            compactWaiterOrderIfNeeded()
            return
        }

        activeCount = max(0, activeCount - 1)
        compactWaiterOrderIfNeeded()
    }

    private func cancelWaiter(_ id: Int) {
        waiters.removeValue(forKey: id)?.resume(returning: false)
        compactWaiterOrderIfNeeded()
    }

    private func compactWaiterOrderIfNeeded() {
        let queuedSlots = waiterOrder.count - waiterHead
        let tombstones = queuedSlots - waiters.count
        guard waiters.isEmpty || (queuedSlots >= 64 && tombstones * 2 >= queuedSlots)
        else { return }

        if waiters.isEmpty {
            waiterOrder.removeAll(keepingCapacity: true)
        } else {
            waiterOrder = waiterOrder[waiterHead...].filter { waiters[$0] != nil }
        }
        waiterHead = 0
    }
}
