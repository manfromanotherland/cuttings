// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Independent, strict byte budgets keep large detail images from evicting board previews.
/// File fingerprints are checked by the off-main loader, never by a view's body.
final class AssetPreviewImageCache: @unchecked Sendable {
    static let shared = AssetPreviewImageCache()
    private let lock = NSLock()
    private var buckets: [Bucket: [AssetPreviewDecodeKey: Entry]] = [:]
    private var costs: [Bucket: Int] = [:]
    private var clock: UInt64 = 0
    private let countLimit: Int
    private let totalCostLimit: Int

    private enum Bucket: CaseIterable {
        case lightweight, board, detail

        init(_ maxPixel: Int) {
            self = maxPixel <= 160 ? .lightweight : maxPixel <= 1024 ? .board : .detail
        }
    }

    private struct Entry {
        let variant: AssetPreviewVariant
        let fingerprint: AssetPreviewSourceFingerprint?
        let cost: Int
        var lastAccess: UInt64
    }

    init(countLimit: Int = 256, totalCostLimit: Int = 128 * 1024 * 1024) {
        self.countLimit = max(1, countLimit)
        self.totalCostLimit = max(0, totalCostLimit)
    }

    func entry(
        for key: AssetPreviewDecodeKey,
        fingerprint: AssetPreviewSourceFingerprint? = nil
    ) -> AssetPreviewVariant? {
        lock.lock()
        defer { lock.unlock() }
        let bucket = Bucket(key.maxPixel)
        guard var entry = buckets[bucket]?[key] else { return nil }
        if let fingerprint, entry.fingerprint != fingerprint {
            buckets[bucket]?.removeValue(forKey: key)
            costs[bucket, default: 0] -= entry.cost
            return nil
        }
        clock &+= 1
        entry.lastAccess = clock
        buckets[bucket]?[key] = entry
        return entry.variant
    }

    func insert(
        _ image: NSImage,
        for key: AssetPreviewDecodeKey,
        fingerprint: AssetPreviewSourceFingerprint? = nil
    ) {
        let cost = pixelCost(for: image)
        let bucket = Bucket(key.maxPixel)
        guard cost <= budget(for: bucket) else { return }
        lock.lock()
        defer { lock.unlock() }
        clock &+= 1
        costs[bucket, default: 0] -= buckets[bucket]?[key]?.cost ?? 0
        buckets[bucket, default: [:]][key] = Entry(
            variant: AssetPreviewVariant(image: image, decodedForMaxPixel: CGFloat(key.maxPixel)),
            fingerprint: fingerprint, cost: cost, lastAccess: clock
        )
        costs[bucket, default: 0] += cost
        while costs[bucket, default: 0] > budget(for: bucket)
            || buckets[bucket, default: [:]].count > countLimit
        {
            guard let oldest = buckets[bucket]?.min(by: { $0.value.lastAccess < $1.value.lastAccess })
            else { break }
            buckets[bucket]?.removeValue(forKey: oldest.key)
            costs[bucket, default: 0] -= oldest.value.cost
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        buckets.removeAll()
        costs.removeAll()
    }

    func storedByteCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return costs.values.reduce(0, +)
    }

    private func budget(for bucket: Bucket) -> Int {
        switch bucket {
        case .lightweight: totalCostLimit / 8
        case .board: totalCostLimit * 5 / 8
        case .detail: totalCostLimit / 4
        }
    }

    private func pixelCost(for image: NSImage) -> Int {
        let cost = image.size.width * image.size.height * 4
        guard cost.isFinite, cost > 0, cost <= CGFloat(Int.max) else { return Int.max }
        return max(1, Int(cost.rounded(.up)))
    }
}
