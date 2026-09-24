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

extension AssetPreviewDecodeQueue {
    nonisolated static func decodeSource(
        at url: URL, maxPixel: CGFloat, kind: AssetPreviewDecodeKey.Kind
    ) async -> AssetImageLoader.Decoded? {
        if kind == .video {
            await AssetImageLoader.videoThumbnail(at: url, maxPixel: maxPixel)
        } else {
            AssetImageLoader.downsampledImage(at: url, maxPixel: maxPixel)
        }
    }

}
