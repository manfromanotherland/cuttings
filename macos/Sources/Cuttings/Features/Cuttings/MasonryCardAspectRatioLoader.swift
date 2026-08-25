// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AVFoundation
import ImageIO

/// The subset of a row that determines its precomputed masonry height. Purely
/// visual metadata such as theme colour and tags is omitted, while same-id
/// article upgrades and external text edits produce a new identity.
struct MasonryCardGeometryIdentity: Hashable, Sendable {
    let id: String
    let kind: String
    let title: String
    let url: String
    let site: String?
    let excerpt: String?
    let previewAsset: String?
    let mediaURL: String?

    init(row: ReadingRow) {
        id = row.id
        kind = row.kind.rawValue
        title = row.title
        url = row.url
        site = row.site
        excerpt = row.excerpt
        previewAsset = row.previewAsset
        mediaURL = row.mediaUrl
    }
}

/// Reads only local image headers so masonry geometry is final before a card
/// enters the collection view. Ratios are immutable for content-addressed
/// assets and stay cached for the lifetime of the app.
actor MasonryCardAspectRatioLoader {
    static let shared = MasonryCardAspectRatioLoader()

    private var ratiosByPath: [String: CGFloat] = [:]

    func aspectRatios(
        for rows: [ReadingRow],
        libraryURL: URL?
    ) async -> [String: CGFloat] {
        let requests = rows.compactMap { Self.request(for: $0, libraryURL: libraryURL) }

        var result: [String: CGFloat] = [:]
        var missing: [Request] = []
        for request in requests {
            if let ratio = ratiosByPath[request.path] {
                result[request.id] = ratio
            } else {
                missing.append(request)
            }
        }

        let loaded = await Self.load(missing)

        for (request, ratio) in loaded {
            guard let ratio else { continue }
            ratiosByPath[request.path] = ratio
            result[request.id] = ratio
        }
        return result
    }

    private nonisolated static func load(
        _ requests: [Request]
    ) async -> [(Request, CGFloat?)] {
        guard !requests.isEmpty else { return [] }

        return await withTaskGroup(
            of: (Request, CGFloat?).self,
            returning: [(Request, CGFloat?)].self
        ) { group in
            var nextRequestIndex = 0
            let workerCount = min(8, requests.count)

            func enqueueNextRequest() {
                guard nextRequestIndex < requests.count else { return }
                let request = requests[nextRequestIndex]
                nextRequestIndex += 1
                group.addTask {
                    guard !Task.isCancelled else { return (request, nil) }
                    return await (request, Self.readAspectRatio(for: request))
                }
            }

            for _ in 0 ..< workerCount {
                enqueueNextRequest()
            }

            var values: [(Request, CGFloat?)] = []
            values.reserveCapacity(requests.count)
            for await value in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    continue
                }
                values.append(value)
                enqueueNextRequest()
            }
            return values
        }
    }

    private nonisolated static func request(
        for row: ReadingRow,
        libraryURL: URL?
    ) -> Request? {
        let source: String
        let kind: RequestKind
        if let previewAsset = row.previewAsset {
            source = previewAsset
            kind = .image
        } else if let videoAsset = localVideoAssetReference(for: row) {
            source = videoAsset
            kind = .video
        } else {
            return nil
        }
        let folder = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL,
            readingID: row.id
        )
        guard let url = AssetImageLoader.localURL(source: source, assetBaseURL: folder)
        else { return nil }
        return Request(id: row.id, path: url.path, url: url, kind: kind)
    }

    private nonisolated static func readAspectRatio(for request: Request) async -> CGFloat? {
        switch request.kind {
        case .image:
            readImageAspectRatio(at: request.url)
        case .video:
            await readVideoAspectRatio(at: request.url)
        }
    }

    private static func localVideoAssetReference(for row: ReadingRow) -> String? {
        let prefix = "cuttings-asset:"
        guard row.kind == .video,
              let mediaURL = row.mediaUrl,
              mediaURL.hasPrefix(prefix)
        else { return nil }
        return String(mediaURL.dropFirst(prefix.count))
    }

    private nonisolated static func readImageAspectRatio(at url: URL) -> CGFloat? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithURL(url as CFURL, options),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options)
           as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
           width > 0,
           height > 0
        {
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
            let swapsAxes = orientation.map { (5 ... 8).contains($0) } ?? false
            return CGFloat(swapsAxes ? height / width : width / height)
        }

        guard url.pathExtension.caseInsensitiveCompare("svg") == .orderedSame,
              let size = NSImage(contentsOf: url)?.size,
              size.width > 0,
              size.height > 0
        else { return nil }
        return size.width / size.height
    }

    private nonisolated static func readVideoAspectRatio(at url: URL) async -> CGFloat? {
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }
            let (naturalSize, preferredTransform) = try await track.load(
                .naturalSize,
                .preferredTransform
            )
            let transformed = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
            let width = abs(transformed.width)
            let height = abs(transformed.height)
            guard width > 0, height > 0 else { return nil }
            return width / height
        } catch {
            return nil
        }
    }

    private enum RequestKind: Sendable {
        case image
        case video
    }

    private struct Request: Sendable {
        let id: String
        let path: String
        let url: URL
        let kind: RequestKind
    }
}
