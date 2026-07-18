// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Drives the full-screen image-zoom overlay. A single presenter is created by
/// `ArticleDetailView` and injected into the reader's environment; tapping a
/// figure (`AssetImageView`) calls `present`, which sets `target`.
/// `ArticleDetailView` observes `target` to show `ImageLightbox`, and clears it
/// on dismiss. Kept as a small `@Observable` (rather than plumbing a binding
/// through every block view) so any figure, however deeply nested in the reader's
/// view tree, can raise the lightbox without threading state by hand.
@Observable
final class ImageZoomPresenter {
    /// The image currently shown in the lightbox, or `nil` when none is open.
    var target: Target?

    /// One presentable image. `localURL` points at the on-disk asset. `id` is
    /// unique per `present` call so the SwiftUI transition animates fresh even
    /// when the same image reopens.
    struct Target: Identifiable, Equatable {
        let id = UUID()
        let alt: String
        let localURL: URL
    }

    /// Open the lightbox for a Markdown image source. Only local library assets
    /// open; a source that never downloaded is still a remote `http(s)` URL —
    /// `localURL` returns nil for it — so this no-ops and the reader keeps showing
    /// its placeholder rather than fetching the image over the network.
    func present(source: String, alt: String, libraryURL: URL?) {
        guard let local = AssetImageLoader.localURL(source: source, libraryURL: libraryURL) else { return }
        target = Target(alt: alt, localURL: local)
    }

    func dismiss() {
        target = nil
    }
}
