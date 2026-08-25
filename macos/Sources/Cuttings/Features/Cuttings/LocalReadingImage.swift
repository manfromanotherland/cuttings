// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Offline-only image rendering for card previews and the image/video overlay.
/// Captured previews are decoded with ImageIO; a local video without a poster
/// derives its thumbnail from the saved movie. Both paths stay beneath the
/// reading's own folder and never reach back to the network.
struct LocalReadingImage: View {
    let row: ReadingRow
    let libraryURL: URL?
    var fallbackAspectRatio: CGFloat = 4 / 3
    var maxPixel: CGFloat = 800
    var contentMode: ContentMode = .fit

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image ?? cachedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(imageAspectRatio(image), contentMode: contentMode)
            } else {
                placeholder
                    .aspectRatio(fallbackAspectRatio, contentMode: .fit)
            }
        }
        .task(id: loadKey) {
            await load()
        }
    }

    private var placeholder: some View {
        ZStack {
            CuttingsTheme.cardTint(for: row.id)
            Image(systemName: failed ? "photo.badge.exclamationmark" : row.kind.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private var loadKey: String {
        "\(row.id):\(row.previewAsset ?? row.localVideoAssetReference ?? ""):\(Int(maxPixel))"
    }

    private var assetURL: URL? {
        let source = row.previewAsset ?? row.localVideoAssetReference
        guard let source else { return nil }
        let baseURL = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL,
            readingID: row.id
        )
        return AssetImageLoader.localURL(source: source, assetBaseURL: baseURL)
    }

    @MainActor
    private var cachedImage: NSImage? {
        guard let assetURL else { return nil }
        return AssetPreviewImageCache.shared.entry(for: assetURL)?.image
    }

    private func imageAspectRatio(_ image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return fallbackAspectRatio }
        return image.size.width / image.size.height
    }

    @MainActor
    private func load() async {
        failed = false
        guard let url = assetURL else {
            image = nil
            return
        }
        if let cached = AssetPreviewImageCache.shared.entry(for: url) {
            image = cached.image
            if cached.decodedForMaxPixel >= maxPixel {
                return
            }
        }

        let loaded = await AssetPreviewPrefetcher.shared.image(
            at: url,
            isVideo: row.previewAsset == nil,
            maxPixel: maxPixel
        )
        guard !Task.isCancelled else { return }
        image = loaded
        failed = loaded == nil
    }
}

@MainActor
final class AssetPreviewImageCache {
    static let shared = AssetPreviewImageCache()

    final class Entry {
        let image: NSImage
        let decodedForMaxPixel: CGFloat

        init(image: NSImage, decodedForMaxPixel: CGFloat) {
            self.image = image
            self.decodedForMaxPixel = decodedForMaxPixel
        }
    }

    private let entries = NSCache<NSString, Entry>()

    private init() {
        entries.countLimit = 512
        entries.totalCostLimit = 256 * 1024 * 1024
    }

    func entry(for url: URL) -> Entry? {
        entries.object(forKey: url.path as NSString)
    }

    func insert(_ image: NSImage, for url: URL, decodedForMaxPixel: CGFloat) {
        if let existing = entry(for: url),
           existing.decodedForMaxPixel >= decodedForMaxPixel
        {
            return
        }
        let entry = Entry(image: image, decodedForMaxPixel: decodedForMaxPixel)
        let pixelCost = Int(image.size.width * image.size.height * 4)
        entries.setObject(entry, forKey: url.path as NSString, cost: pixelCost)
    }
}

@MainActor
final class AssetPreviewPrefetcher {
    static let shared = AssetPreviewPrefetcher()

    private var tasks: [String: InFlight] = [:]

    func prefetch(
        rows: [ReadingRow],
        libraryURL: URL?,
        maxPixel: CGFloat
    ) {
        for row in rows {
            guard let request = request(for: row, libraryURL: libraryURL, maxPixel: maxPixel)
            else { continue }
            if let cached = AssetPreviewImageCache.shared.entry(for: request.url),
               cached.decodedForMaxPixel >= request.maxPixel
            {
                continue
            }
            if var existing = tasks[request.key] {
                existing.isPrefetchRequested = true
                tasks[request.key] = existing
                continue
            }
            start(request, priority: .utility, isPrefetchRequested: true)
        }
    }

    /// Visible cards and collection-view prefetches share one decode task. A
    /// card entering quickly therefore waits for the warmup already in flight
    /// instead of consuming a second slot in the bounded decoder.
    func image(at url: URL, isVideo: Bool, maxPixel: CGFloat) async -> NSImage? {
        if let cached = AssetPreviewImageCache.shared.entry(for: url),
           cached.decodedForMaxPixel >= maxPixel
        {
            return cached.image
        }

        let request = Request(
            key: Self.requestKey(url: url, maxPixel: maxPixel),
            url: url,
            isVideo: isVideo,
            maxPixel: maxPixel
        )
        if tasks[request.key] == nil {
            start(request, priority: .userInitiated, isPrefetchRequested: false)
        }
        guard var entry = tasks[request.key] else { return nil }
        entry.visibleWaiters += 1
        tasks[request.key] = entry
        let token = entry.token
        await entry.task.value

        if var current = tasks[request.key], current.token == token {
            current.visibleWaiters = max(0, current.visibleWaiters - 1)
            tasks[request.key] = current
        }
        guard !Task.isCancelled else { return nil }
        return AssetPreviewImageCache.shared.entry(for: url)?.image
    }

    func cancel(
        rows: [ReadingRow],
        libraryURL: URL?,
        maxPixel: CGFloat
    ) {
        for row in rows {
            guard let request = request(for: row, libraryURL: libraryURL, maxPixel: maxPixel)
            else { continue }
            guard var entry = tasks[request.key] else { continue }
            entry.isPrefetchRequested = false
            if entry.visibleWaiters == 0 {
                tasks.removeValue(forKey: request.key)?.task.cancel()
            } else {
                tasks[request.key] = entry
            }
        }
    }

    private func start(
        _ request: Request,
        priority: TaskPriority,
        isPrefetchRequested: Bool
    ) {
        let token = UUID()
        let task = Task(priority: priority) { [weak self] in
            defer { self?.finish(key: request.key, token: token) }
            let decoded: AssetImageLoader.Decoded? = if request.isVideo {
                await AssetPreviewDecodeQueue.shared.videoThumbnail(
                    at: request.url,
                    maxPixel: request.maxPixel
                )
            } else {
                await AssetPreviewDecodeQueue.shared.image(
                    at: request.url,
                    maxPixel: request.maxPixel
                )
            }
            guard !Task.isCancelled, let decoded else { return }
            AssetPreviewImageCache.shared.insert(
                decoded.image,
                for: request.url,
                decodedForMaxPixel: request.maxPixel
            )
        }
        tasks[request.key] = InFlight(
            token: token,
            task: task,
            isPrefetchRequested: isPrefetchRequested,
            visibleWaiters: 0
        )
    }

    private func finish(key: String, token: UUID) {
        guard tasks[key]?.token == token else { return }
        tasks[key] = nil
    }

    private func request(
        for row: ReadingRow,
        libraryURL: URL?,
        maxPixel: CGFloat
    ) -> Request? {
        let source = row.previewAsset ?? row.localVideoAssetReference
        guard let source else { return nil }
        let folder = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL,
            readingID: row.id
        )
        guard let url = AssetImageLoader.localURL(source: source, assetBaseURL: folder)
        else { return nil }
        return Request(
            key: Self.requestKey(url: url, maxPixel: maxPixel),
            url: url,
            isVideo: row.previewAsset == nil,
            maxPixel: maxPixel
        )
    }

    private static func requestKey(url: URL, maxPixel: CGFloat) -> String {
        "\(url.path):\(Int(maxPixel))"
    }

    private struct InFlight {
        let token: UUID
        let task: Task<Void, Never>
        var isPrefetchRequested: Bool
        var visibleWaiters: Int
    }

    private struct Request {
        let key: String
        let url: URL
        let isVideo: Bool
        let maxPixel: CGFloat
    }
}
