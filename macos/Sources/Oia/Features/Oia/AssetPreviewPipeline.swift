// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class BoardScrollState {
    var isScrolling = false

    func setScrolling(_ isScrolling: Bool) {
        guard self.isScrolling != isScrolling else { return }
        self.isScrolling = isScrolling
    }
}

struct BoardScrollTrackingModifier: ViewModifier {
    let scrollState: BoardScrollState

    func body(content: Content) -> some View {
        content
            .onAppear { scrollState.setScrolling(false) }
            .onScrollPhaseChange { _, phase in
                scrollState.setScrolling(phase.isScrolling)
            }
            .onDisappear { scrollState.setScrolling(false) }
    }
}

struct CardViewportVisibilityModifier: ViewModifier {
    let isEnabled: Bool
    let viewportSize: CGSize
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.onGeometryChange(for: Bool.self) { proxy in
                VideoCardViewport.containsVisibleArea(
                    of: proxy.frame(in: .scrollView(axis: .vertical)),
                    in: CGRect(origin: .zero, size: viewportSize)
                )
            } action: { visible in
                isVisible = visible
            }
        } else {
            content
        }
    }
}

enum AssetPreviewQuality: Hashable {
    case lightweight
    case display
}

struct AssetPreviewLoadPlan: Equatable {
    static let lightweightMaxPixel: CGFloat = 160
    static let boardDisplayMaxPixel: CGFloat = 1024
    static let refinementDelay = Duration.milliseconds(120)
    private static let maximumDecodeMaxPixel = CGFloat(Int32.max)
    let initialMaxPixel: CGFloat?
    let refinementMaxPixel: CGFloat?

    init(
        maxPixel: CGFloat,
        loadsProgressively: Bool,
        isVisible: Bool,
        isScrolling: Bool
    ) {
        guard isVisible else {
            initialMaxPixel = nil
            refinementMaxPixel = nil
            return
        }

        let boundedMaxPixel = maxPixel.isFinite
            ? min(max(1, maxPixel.rounded(.up)), Self.maximumDecodeMaxPixel)
            : 1
        guard loadsProgressively else {
            initialMaxPixel = boundedMaxPixel
            refinementMaxPixel = nil
            return
        }

        let lightweightMaxPixel = min(Self.lightweightMaxPixel, boundedMaxPixel)
        initialMaxPixel = lightweightMaxPixel
        refinementMaxPixel = !isScrolling && boundedMaxPixel > lightweightMaxPixel
            ? boundedMaxPixel
            : nil
    }

    static func displayMaxPixel(for size: CGSize, displayScale: CGFloat) -> CGFloat {
        let dimension = max(size.width, size.height)
        guard dimension.isFinite, dimension > 0 else { return 1 }
        let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
        return min(
            boardDisplayMaxPixel,
            max(1, (dimension * scale).rounded(.up))
        )
    }
}

struct AssetPreviewVariant {
    let image: NSImage
    let decodedForMaxPixel: CGFloat
}

struct AssetPreviewPresentation {
    private(set) var requestURL: URL?
    private(set) var lightweight: AssetPreviewVariant?
    private(set) var display: AssetPreviewVariant?
    private(set) var failed = false

    mutating func reset(for requestURL: URL?) {
        guard self.requestURL != requestURL else { return }
        self = AssetPreviewPresentation(requestURL: requestURL)
    }

    mutating func clear(for requestURL: URL?) {
        self = AssetPreviewPresentation(requestURL: requestURL)
    }

    mutating func publish(
        _ variant: AssetPreviewVariant,
        quality: AssetPreviewQuality,
        for requestURL: URL
    ) {
        reset(for: requestURL)
        switch quality {
        case .lightweight:
            lightweight = variant
        case .display:
            display = variant
        }
        failed = false
    }

    mutating func markFailed(for requestURL: URL?) {
        reset(for: requestURL)
        failed = true
    }

    func variant(
        for quality: AssetPreviewQuality,
        requestURL: URL?,
        isVisible: Bool
    ) -> AssetPreviewVariant? {
        guard isVisible, self.requestURL == requestURL else { return nil }
        return switch quality {
        case .lightweight:
            lightweight
        case .display:
            display ?? lightweight
        }
    }

    func contains(
        _ quality: AssetPreviewQuality,
        atLeastMaxPixel maxPixel: CGFloat,
        for requestURL: URL
    ) -> Bool {
        guard self.requestURL == requestURL else { return false }
        let variant = switch quality {
        case .lightweight: lightweight
        case .display: display
        }
        return (variant?.decodedForMaxPixel ?? 0) >= maxPixel
    }
}

/// A byte-bounded cache of exact-size decoded previews. Reading assets are
/// content-addressed, so their local URL is a stable identity for the lifetime
/// of the app. Including the requested pixel bound keeps a detail image from
/// being attached to a board card and lets decode jobs publish before they
/// leave the in-flight registry. `NSCache` is thread-safe.
final class AssetPreviewImageCache: @unchecked Sendable {
    static let shared = AssetPreviewImageCache()

    private final class Entry {
        let variant: AssetPreviewVariant

        init(variant: AssetPreviewVariant) {
            self.variant = variant
        }
    }

    private let entries = NSCache<NSString, Entry>()

    init(countLimit: Int = 256, totalCostLimit: Int = 128 * 1024 * 1024) {
        entries.countLimit = countLimit
        entries.totalCostLimit = totalCostLimit
    }

    func entry(for key: AssetPreviewDecodeKey) -> AssetPreviewVariant? {
        entries.object(forKey: cacheKey(for: key))?.variant
    }

    func insert(_ image: NSImage, for key: AssetPreviewDecodeKey) {
        let variant = AssetPreviewVariant(
            image: image,
            decodedForMaxPixel: CGFloat(key.maxPixel)
        )
        entries.setObject(
            Entry(variant: variant),
            forKey: cacheKey(for: key),
            cost: pixelCost(for: image)
        )
    }

    private func cacheKey(for key: AssetPreviewDecodeKey) -> NSString {
        let kind = switch key.kind {
        case .image: "image"
        case .video: "video"
        }
        return "\(kind):\(key.maxPixel):\(key.path)" as NSString
    }

    private func pixelCost(for image: NSImage) -> Int {
        let cost = image.size.width * image.size.height * 4
        guard cost.isFinite, cost > 0, cost <= CGFloat(Int.max) else { return 1 }
        return max(1, Int(cost.rounded(.up)))
    }
}
