// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

struct AssetPreviewDecodeKey: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case image
        case video
    }

    let kind: Kind
    let path: String
    let maxPixel: Int

    init(kind: Kind, url: URL, maxPixel: CGFloat) {
        self.kind = kind
        path = url.standardizedFileURL.path
        let boundedMaxPixel = maxPixel.isFinite
            ? min(max(1, maxPixel.rounded(.up)), CGFloat(Int32.max))
            : 1
        self.maxPixel = Int(boundedMaxPixel)
    }
}

/// Bounds board preview work so opening a page cannot decode dozens of large
/// images simultaneously. A permit is handed directly to the next waiter,
/// keeping at most four ImageIO/AVFoundation decodes live at once. Requests for
/// the same asset and pixel bound share one in-flight task, so view churn never
/// starts duplicate work in another permit slot. Completed results enter the
/// exact-size cache before the in-flight job is removed.
actor AssetPreviewDecodeQueue {
    /// Lightweight previews and favicons can use three lanes while one
    /// independent lane refines a settled board card. This keeps total preview
    /// decoding at the existing four-work ceiling without letting refinements
    /// queue ahead of newly visible cards.
    static let shared = AssetPreviewDecodeQueue(limit: 3)
    static let refinement = AssetPreviewDecodeQueue(limit: 1)

    private let limit: Int
    private var active = 0
    private var nextWaiterID = 0
    private var waiters: [Int: CheckedContinuation<Bool, Never>] = [:]
    private var waiterOrder: [Int] = []
    private var waiterHead = 0
    private var nextDecodeJobID = 0
    private var nextDecodeSubscriberID = 0
    private var decodeJobs: [AssetPreviewDecodeKey: DecodeJob] = [:]

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func image(at url: URL, maxPixel: CGFloat) async -> AssetImageLoader.Decoded? {
        let key = AssetPreviewDecodeKey(kind: .image, url: url, maxPixel: maxPixel)
        return await decode(key: key) {
            if let cached = AssetPreviewImageCache.shared.entry(for: key) {
                return AssetImageLoader.Decoded(image: cached.image)
            }
            return await Task.detached(priority: .utility) {
                let decoded = AssetImageLoader.downsampledImage(
                    at: url,
                    maxPixel: CGFloat(key.maxPixel)
                )
                if let decoded {
                    AssetPreviewImageCache.shared.insert(decoded.image, for: key)
                }
                return decoded
            }.value
        }
    }

    func videoThumbnail(at url: URL, maxPixel: CGFloat) async -> AssetImageLoader.Decoded? {
        let key = AssetPreviewDecodeKey(kind: .video, url: url, maxPixel: maxPixel)
        return await decode(key: key) {
            if let cached = AssetPreviewImageCache.shared.entry(for: key) {
                return AssetImageLoader.Decoded(image: cached.image)
            }
            let decoded = await AssetImageLoader.videoThumbnail(
                at: url,
                maxPixel: CGFloat(key.maxPixel)
            )
            if let decoded {
                AssetPreviewImageCache.shared.insert(decoded.image, for: key)
            }
            return decoded
        }
    }

    func decode(
        key: AssetPreviewDecodeKey,
        operation: @escaping @Sendable () async -> AssetImageLoader.Decoded?
    ) async -> AssetImageLoader.Decoded? {
        guard !Task.isCancelled else { return nil }

        let subscriberID = nextDecodeSubscriberID
        nextDecodeSubscriberID += 1
        let job = subscribe(
            subscriberID,
            to: key,
            operation: operation
        )

        return await withTaskCancellationHandler {
            await job.task.value
        } onCancel: {
            Task {
                await self.cancelDecodeSubscriber(
                    subscriberID,
                    jobID: job.id,
                    key: key
                )
            }
        }
    }

    private func subscribe(
        _ subscriberID: Int,
        to key: AssetPreviewDecodeKey,
        operation: @escaping @Sendable () async -> AssetImageLoader.Decoded?
    ) -> DecodeJob {
        if var existing = decodeJobs[key] {
            existing.subscribers.insert(subscriberID)
            decodeJobs[key] = existing
            return existing
        }

        let jobID = nextDecodeJobID
        nextDecodeJobID += 1
        let task = Task {
            await self.runDecodeJob(
                id: jobID,
                key: key,
                operation: operation
            )
        }
        let job = DecodeJob(
            id: jobID,
            isActive: false,
            subscribers: [subscriberID],
            task: task
        )
        decodeJobs[key] = job
        return job
    }

    func state() -> State {
        let queuedSlots = waiterOrder.count - waiterHead
        return State(
            active: active,
            waiting: waiters.count,
            queuedSlots: queuedSlots,
            inFlightDecodes: decodeJobs.count,
            coalescedWaiters: decodeJobs.values.reduce(0) { count, job in
                count + max(0, job.subscribers.count - 1)
            }
        )
    }

    func withPermit<T: Sendable>(
        _ operation: @Sendable () async -> T
    ) async -> T? {
        guard await acquire() else { return nil }
        defer { release() }
        guard !Task.isCancelled else { return nil }
        let result = await operation()
        return Task.isCancelled ? nil : result
    }

    private func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if active < limit {
            active += 1
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

    private func runDecodeJob(
        id: Int,
        key: AssetPreviewDecodeKey,
        operation: @escaping @Sendable () async -> AssetImageLoader.Decoded?
    ) async -> AssetImageLoader.Decoded? {
        guard await acquire() else {
            finishDecodeJob(id: id, key: key)
            return nil
        }

        guard var job = decodeJobs[key], job.id == id else {
            release()
            return nil
        }
        job.isActive = true
        decodeJobs[key] = job

        let decoded = await operation()
        release()
        finishDecodeJob(id: id, key: key)
        return decoded
    }

    private func cancelDecodeSubscriber(
        _ subscriberID: Int,
        jobID: Int,
        key: AssetPreviewDecodeKey
    ) {
        guard var job = decodeJobs[key], job.id == jobID else { return }
        job.subscribers.remove(subscriberID)
        guard job.subscribers.isEmpty else {
            decodeJobs[key] = job
            return
        }
        guard !job.isActive else {
            // ImageIO cannot interrupt a thumbnail already being created. Keep
            // this bounded job keyed so a replacement shares it and its result
            // reaches the exact-size cache instead of starting duplicate work.
            decodeJobs[key] = job
            return
        }

        decodeJobs.removeValue(forKey: key)
        job.task.cancel()
    }

    private func finishDecodeJob(id: Int, key: AssetPreviewDecodeKey) {
        guard decodeJobs[key]?.id == id else { return }
        decodeJobs.removeValue(forKey: key)
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
        active = max(0, active - 1)
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

    struct State: Sendable {
        let active: Int
        let waiting: Int
        let queuedSlots: Int
        let inFlightDecodes: Int
        let coalescedWaiters: Int
    }

    private struct DecodeJob {
        let id: Int
        var isActive: Bool
        var subscribers: Set<Int>
        let task: Task<AssetImageLoader.Decoded?, Never>
    }
}
