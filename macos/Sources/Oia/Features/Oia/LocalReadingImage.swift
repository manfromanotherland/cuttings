// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Offline-only image rendering for card previews, source-profile attachments,
/// and the image/video overlay. Captured previews are decoded with ImageIO; a
/// local video without a poster derives its thumbnail from the saved movie.
/// Every path stays beneath the reading's own folder and never reaches back to
/// the network.
struct LocalReadingImage: View {
    let row: ReadingRow
    let libraryURL: URL?
    var explicitAssetReference: String?
    var explicitAssetIsVideo = false
    var fallbackAspectRatio: CGFloat = 4 / 3
    var maxPixel: CGFloat = 800
    var contentMode: ContentMode = .fit
    var loadsProgressively = false
    var isVisible = true
    var scrollState: BoardScrollState?

    @State private var presentation = AssetPreviewPresentation()

    var body: some View {
        Group {
            if let image = presentedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(loadsProgressively && isScrolling ? .low : .high)
                    .aspectRatio(imageAspectRatio(image), contentMode: contentMode)
            } else {
                placeholder
                    .aspectRatio(fallbackAspectRatio, contentMode: contentMode)
            }
        }
        .task(id: initialTaskID) {
            await loadInitialVariant()
        }
        .task(id: refinementTaskID) {
            await loadDisplayVariant()
        }
        .onDisappear {
            presentation.clear(for: nil)
        }
    }

    private var placeholder: some View {
        ZStack {
            OiaTheme.previewPlaceholderBackground(for: row)
            if showsFailure {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(OiaTheme.previewPlaceholderForeground(for: row))
            }
        }
    }

    private var presentedImage: NSImage? {
        guard isVisible else { return nil }
        let quality: AssetPreviewQuality = loadsProgressively && isScrolling
            ? .lightweight
            : .display
        return presentation.variant(
            for: quality,
            requestURL: assetRequest?.url,
            isVisible: true
        )?.image
    }

    private var showsFailure: Bool {
        isVisible
            && presentation.requestURL == assetRequest?.url
            && presentation.failed
    }

    private var isScrolling: Bool {
        scrollState?.isScrolling ?? false
    }

    private var initialPlan: AssetPreviewLoadPlan {
        AssetPreviewLoadPlan(
            maxPixel: maxPixel,
            loadsProgressively: loadsProgressively,
            isVisible: isVisible,
            isScrolling: true
        )
    }

    private var refinementPlan: AssetPreviewLoadPlan {
        AssetPreviewLoadPlan(
            maxPixel: maxPixel,
            loadsProgressively: loadsProgressively,
            isVisible: isVisible,
            isScrolling: isVisible ? isScrolling : false
        )
    }

    private var initialTaskID: LoadTaskID {
        LoadTaskID(
            request: assetRequest,
            maxPixel: initialPlan.initialMaxPixel,
            quality: loadsProgressively ? .lightweight : .display,
            prerequisiteIsReady: true
        )
    }

    private var refinementTaskID: LoadTaskID {
        let request = assetRequest
        let refinementMaxPixel = refinementPlan.refinementMaxPixel
        let lightweightIsReady = if let request, let refinementMaxPixel {
            presentation.contains(
                .lightweight,
                atLeastMaxPixel: min(
                    AssetPreviewLoadPlan.lightweightMaxPixel,
                    refinementMaxPixel
                ),
                for: request.url
            )
        } else {
            false
        }
        return LoadTaskID(
            request: request,
            maxPixel: refinementMaxPixel,
            quality: .display,
            prerequisiteIsReady: lightweightIsReady
        )
    }
}

private extension LocalReadingImage {
    private func imageAspectRatio(_ image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return fallbackAspectRatio }
        return image.size.width / image.size.height
    }

    @MainActor
    private func loadInitialVariant() async {
        let request = assetRequest
        guard isVisible else {
            presentation.clear(for: request?.url)
            return
        }
        guard let request, let initialMaxPixel = initialPlan.initialMaxPixel else {
            presentation.markFailed(for: request?.url)
            return
        }

        let quality: AssetPreviewQuality = loadsProgressively ? .lightweight : .display
        presentation.reset(for: request.url)
        guard !presentation.contains(
            quality,
            atLeastMaxPixel: initialMaxPixel,
            for: request.url
        ) else { return }

        let key = decodeKey(request, maxPixel: initialMaxPixel)
        if let cached = AssetPreviewImageCache.shared.entry(for: key) {
            presentation.publish(cached, quality: quality, for: request.url)
            return
        }

        let decoded = await decode(request, maxPixel: initialMaxPixel, queue: .shared)
        completeInitialDecode(
            decoded,
            request: request,
            maxPixel: initialMaxPixel,
            quality: quality
        )
    }

    @MainActor
    private func completeInitialDecode(
        _ decoded: AssetImageLoader.Decoded?,
        request: AssetRequest,
        maxPixel: CGFloat,
        quality: AssetPreviewQuality
    ) {
        guard let decoded else {
            guard !Task.isCancelled, assetRequest == request, isVisible else { return }
            presentation.markFailed(for: request.url)
            return
        }
        let variant = AssetPreviewVariant(
            image: decoded.image,
            decodedForMaxPixel: maxPixel
        )
        guard !Task.isCancelled, assetRequest == request, isVisible else { return }
        presentation.publish(variant, quality: quality, for: request.url)
    }

    @MainActor
    private func loadDisplayVariant() async {
        guard refinementTaskID.prerequisiteIsReady,
              let request = assetRequest,
              let refinementMaxPixel = refinementPlan.refinementMaxPixel
        else { return }

        do {
            try await Task.sleep(for: AssetPreviewLoadPlan.refinementDelay)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        let key = decodeKey(request, maxPixel: refinementMaxPixel)
        if let cached = AssetPreviewImageCache.shared.entry(for: key) {
            guard assetRequest == request, !isScrolling, isVisible else { return }
            presentation.publish(cached, quality: .display, for: request.url)
            return
        }

        let decoded = await decode(
            request, maxPixel: refinementMaxPixel, queue: .refinement
        )
        completeDisplayDecode(
            decoded,
            request: request,
            maxPixel: refinementMaxPixel
        )
    }

    @MainActor
    private func completeDisplayDecode(
        _ decoded: AssetImageLoader.Decoded?,
        request: AssetRequest,
        maxPixel: CGFloat
    ) {
        guard let decoded else { return }
        let variant = AssetPreviewVariant(
            image: decoded.image,
            decodedForMaxPixel: maxPixel
        )
        guard !Task.isCancelled,
              assetRequest == request,
              !isScrolling,
              isVisible
        else { return }
        presentation.publish(variant, quality: .display, for: request.url)
    }

    private var assetRequest: AssetRequest? {
        let source: String
        let isVideo: Bool
        if let explicitAssetReference {
            source = explicitAssetReference
            isVideo = explicitAssetIsVideo
        } else if let previewAsset = row.previewAsset {
            source = previewAsset
            isVideo = false
        } else if let videoAsset = row.localVideoAssetReference {
            source = videoAsset
            isVideo = true
        } else {
            return nil
        }

        let baseURL = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL, readingID: row.id
        )
        guard let url = AssetImageLoader.localURL(source: source, assetBaseURL: baseURL)
        else { return nil }
        return AssetRequest(url: url, isVideo: isVideo)
    }

    private func decode(
        _ request: AssetRequest,
        maxPixel: CGFloat,
        queue: AssetPreviewDecodeQueue
    ) async -> AssetImageLoader.Decoded? {
        if request.isVideo {
            return await queue.videoThumbnail(at: request.url, maxPixel: maxPixel)
        }
        return await queue.image(at: request.url, maxPixel: maxPixel)
    }

    private func decodeKey(
        _ request: AssetRequest,
        maxPixel: CGFloat
    ) -> AssetPreviewDecodeKey {
        AssetPreviewDecodeKey(
            kind: request.isVideo ? .video : .image,
            url: request.url,
            maxPixel: maxPixel
        )
    }

    private struct AssetRequest: Hashable {
        let url: URL
        let isVideo: Bool
    }

    private struct LoadTaskID: Hashable {
        let request: AssetRequest?
        let maxPixel: Int?
        let quality: AssetPreviewQuality
        let prerequisiteIsReady: Bool

        init(
            request: AssetRequest?,
            maxPixel: CGFloat?,
            quality: AssetPreviewQuality,
            prerequisiteIsReady: Bool
        ) {
            self.request = request
            self.maxPixel = maxPixel.map { Int($0.rounded(.up)) }
            self.quality = quality
            self.prerequisiteIsReady = prerequisiteIsReady
        }
    }
}
