// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A page favicon rendered from the reading's own local `assets/` folder. It
/// deliberately shares the same resolver, bounded decoder, and cache as card
/// previews; the browser is never consulted while the board is rendering.
struct LocalReadingFavicon: View {
    let row: ReadingRow
    let libraryURL: URL?
    var size: CGFloat = 14
    var maxPixel: CGFloat = 64

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(fallbackForeground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
        .task(id: loadKey) {
            await load()
        }
    }

    private var loadKey: String {
        "\(row.id):\(row.faviconAsset ?? ""):\(Int(maxPixel))"
    }

    private var assetURL: URL? {
        guard let source = row.faviconAsset else { return nil }
        let folder = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL,
            readingID: row.id
        )
        return AssetImageLoader.localURL(source: source, assetBaseURL: folder)
    }

    private var fallbackForeground: Color {
        CuttingsTheme.articlePalette(for: row)?.foreground.color ?? .secondary
    }

    @MainActor
    private func load() async {
        guard let url = assetURL else {
            image = nil
            return
        }
        let loaded = await AssetPreviewDecodeQueue.shared.image(at: url, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        image = loaded?.image
    }
}
