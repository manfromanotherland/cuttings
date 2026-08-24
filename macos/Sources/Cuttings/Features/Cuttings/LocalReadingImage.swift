// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Offline-only image rendering for card previews and the image/video overlay.
/// `previewAsset` is resolved beneath the reading's own folder and decoded with
/// ImageIO, so the board never reaches back to the network or materializes a
/// needlessly full-resolution bitmap.
struct LocalReadingImage: View {
    let row: ReadingRow
    let libraryURL: URL?
    var fallbackAspectRatio: CGFloat = 4 / 3
    var maxPixel: CGFloat = 1600
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
        "\(row.id):\(row.previewAsset ?? ""):\(Int(maxPixel))"
    }

    private func imageAspectRatio(_ image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return fallbackAspectRatio }
        return image.size.width / image.size.height
    }

    @MainActor
    private func load() async {
        image = nil
        failed = false
        let baseURL = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL, readingID: row.id
        )
        // A local video intentionally has no poster in the first implementation;
        // its kind glyph is the expected placeholder, not a failed-image state.
        guard let source = row.previewAsset else { return }
        guard let url = AssetImageLoader.localURL(source: source, assetBaseURL: baseURL) else {
            failed = true
            return
        }
        let target = maxPixel
        let decoded = await Task.detached {
            AssetImageLoader.downsampledImage(at: url, maxPixel: target)
        }.value
        guard !Task.isCancelled else { return }
        image = decoded?.image
        failed = decoded == nil
    }
}
