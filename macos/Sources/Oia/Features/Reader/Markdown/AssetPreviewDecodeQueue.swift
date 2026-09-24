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
    /// Two visible lanes, one refinement lane, and one speculative lane keep
    /// total original decoding bounded at four without prefetch queuing ahead
    /// of newly visible cards. Every lane shares a source-work registry.
    static let shared = AssetPreviewDecodeQueue(limit: 2)
    static let refinement = AssetPreviewDecodeQueue(limit: 1)
    static let prefetch = AssetPreviewDecodeQueue(limit: 1, priority: .background)
    private static let sourceWork = AssetPreviewDecodeQueue(limit: 4)

    private let limit: Int
    private let priority: TaskPriority
    private let diskCache: AssetPreviewDiskCache
    private var active = 0
    private var nextWaiterID = 0
    private var waiters: [Int: CheckedContinuation<Bool, Never>] = [:]
    private var waiterOrder: [Int] = []
    private var waiterHead = 0
    private var nextDecodeJobID = 0
    private var nextDecodeSubscriberID = 0
    private var decodeJobs: [AssetPreviewDecodeKey: DecodeJob] = [:]

    init(
        limit: Int,
        priority: TaskPriority = .utility,
        diskCache: AssetPreviewDiskCache = .shared
    ) {
        self.limit = max(1, limit)
        self.priority = priority
        self.diskCache = diskCache
    }

    func image(at url: URL, maxPixel: CGFloat) async -> AssetImageLoader.Decoded? {
        await preview(at: url, maxPixel: maxPixel, kind: .image)
    }

    func videoThumbnail(at url: URL, maxPixel: CGFloat) async -> AssetImageLoader.Decoded? {
        await preview(at: url, maxPixel: maxPixel, kind: .video)
    }

    /// Warm-cache lookup only. No original image decode or video frame extraction.
    func cachedPreview(
        at url: URL, maxPixel: CGFloat, kind: AssetPreviewDecodeKey.Kind
    ) async -> AssetImageLoader.Decoded? {
        let key = AssetPreviewDecodeKey(kind: kind, url: url, maxPixel: maxPixel)
        let diskCache = diskCache
        let priority = priority
        return await withPermit {
            await Task.detached(priority: priority) {
                guard let fingerprint = AssetPreviewSourceFingerprint.read(at: url) else { return nil }
                return Self.cached(key, fingerprint: fingerprint, diskCache: diskCache)
            }.value
        } ?? nil
    }

    private func preview(
        at url: URL, maxPixel: CGFloat, kind: AssetPreviewDecodeKey.Kind
    ) async -> AssetImageLoader.Decoded? {
        let key = AssetPreviewDecodeKey(kind: kind, url: url, maxPixel: maxPixel)
        let priority = priority
        let diskCache = diskCache
        return await decode(key: key) {
            // All lanes share the final in-flight registry. Cancelling speculative
            // subscribers cannot cancel a visible subscriber's source decode.
            await Self.sourceWork.decode(key: key) {
                await Task.detached(priority: priority) {
                    guard let fingerprint = AssetPreviewSourceFingerprint.read(at: url) else { return nil }
                    if let cached = Self.cached(key, fingerprint: fingerprint, diskCache: diskCache) {
                        return cached
                    }
                    PerformanceTrace.increment("preview_source_decodes")
                    let interval = PerformanceTrace.begin("PreviewDecode")
                    let decoded: AssetImageLoader.Decoded? = if kind == .video {
                        await AssetImageLoader.videoThumbnail(at: url, maxPixel: CGFloat(key.maxPixel))
                    } else {
                        AssetImageLoader.downsampledImage(at: url, maxPixel: CGFloat(key.maxPixel))
                    }
                    PerformanceTrace.end("PreviewDecode", interval)
                    guard let decoded,
                          AssetPreviewSourceFingerprint.read(at: url) == fingerprint else { return nil }
                    AssetPreviewImageCache.shared.insert(decoded.image, for: key, fingerprint: fingerprint)
                    diskCache.scheduleStore(decoded, for: AssetPreviewDiskKey(key, fingerprint: fingerprint))
                    return decoded
                }.value
            }
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

private extension AssetPreviewDecodeQueue {
    nonisolated static func cached(
        _ key: AssetPreviewDecodeKey,
        fingerprint: AssetPreviewSourceFingerprint,
        diskCache: AssetPreviewDiskCache
    ) -> AssetImageLoader.Decoded? {
        if let cached = AssetPreviewImageCache.shared.entry(for: key, fingerprint: fingerprint) {
            PerformanceTrace.increment("preview_memory_hits")
            return AssetImageLoader.Decoded(image: cached.image)
        }
        guard let decoded = diskCache.image(for: AssetPreviewDiskKey(key, fingerprint: fingerprint)) else {
            PerformanceTrace.increment("preview_cache_misses")
            return nil
        }
        AssetPreviewImageCache.shared.insert(decoded.image, for: key, fingerprint: fingerprint)
        return decoded
    }
}
