// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Spaces idle-quality view updates independently of decode completion. Initial
/// visible previews bypass this queue. Cancelled refinements leave immediately.
actor AssetPreviewPublicationQueue {
    static let shared = AssetPreviewPublicationQueue()
    private let maximumPerBatch: Int
    private let waitForBatch: @Sendable () async throws -> Void
    private var nextID = 0
    private var waiters: [Int: CheckedContinuation<Bool, Never>] = [:]
    private var order: [Int] = []
    private var pump: Task<Void, Never>?

    init(maximumPerBatch: Int = 2, interval: Duration = .milliseconds(12)) {
        self.maximumPerBatch = max(1, maximumPerBatch)
        waitForBatch = { try await Task.sleep(for: interval) }
    }

    init(maximumPerBatch: Int, waitForBatch: @escaping @Sendable () async throws -> Void) {
        self.maximumPerBatch = max(1, maximumPerBatch)
        self.waitForBatch = waitForBatch
    }

    func waitForTurn() async -> Bool {
        guard !Task.isCancelled else { return false }
        let id = nextID
        nextID += 1
        let admitted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters[id] = continuation
                order.append(id)
                if pump == nil {
                    pump = Task { await self.publishBatches() }
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        return admitted && !Task.isCancelled
    }

    func waitingCount() -> Int {
        waiters.count
    }

    private func cancel(_ id: Int) {
        waiters.removeValue(forKey: id)?.resume(returning: false)
        order.removeAll { $0 == id }
    }

    private func publishBatches() async {
        defer { pump = nil }
        while !waiters.isEmpty {
            do {
                try await waitForBatch()
            } catch {
                let pending = waiters.values
                waiters.removeAll()
                order.removeAll()
                pending.forEach { $0.resume(returning: false) }
                return
            }
            let batch = Array(order.prefix(maximumPerBatch))
            order.removeFirst(batch.count)
            for id in batch {
                waiters.removeValue(forKey: id)?.resume(returning: true)
            }
        }
    }
}
