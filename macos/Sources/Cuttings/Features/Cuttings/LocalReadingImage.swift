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
            if let image {
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
        .onDisappear {
            image = nil
        }
    }

    private var placeholder: some View {
        ZStack {
            CuttingsTheme.cardBackground(for: row)
            Image(systemName: failed ? "photo.badge.exclamationmark" : row.kind.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(
                    CuttingsTheme.articlePalette(for: row)?.foreground.color ?? .secondary
                )
        }
    }

    private var loadKey: String {
        "\(row.id):\(row.previewAsset ?? row.localVideoAssetReference ?? ""):\(Int(maxPixel))"
    }

    private func imageAspectRatio(_ image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return fallbackAspectRatio }
        return image.size.width / image.size.height
    }

    @MainActor
    private func load() async {
        failed = false
        let baseURL = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL, readingID: row.id
        )
        let decoded: AssetImageLoader.Decoded?
        if let source = row.previewAsset {
            guard let url = AssetImageLoader.localURL(source: source, assetBaseURL: baseURL) else {
                image = nil
                failed = true
                return
            }
            decoded = await AssetPreviewDecodeQueue.shared.image(at: url, maxPixel: maxPixel)
        } else if let source = row.localVideoAssetReference {
            guard let url = AssetImageLoader.localURL(source: source, assetBaseURL: baseURL) else {
                image = nil
                failed = true
                return
            }
            decoded = await AssetPreviewDecodeQueue.shared.videoThumbnail(
                at: url, maxPixel: maxPixel
            )
        } else {
            image = nil
            return
        }
        guard !Task.isCancelled else { return }
        image = decoded?.image
        failed = decoded == nil
    }
}
