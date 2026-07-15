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

    /// One presentable image. `remoteURL` is set for `http(s)` sources; otherwise
    /// `localURL` points at the on-disk asset. `id` is unique per `present` call
    /// so the SwiftUI transition animates fresh even when the same image reopens.
    struct Target: Identifiable, Equatable {
        let id = UUID()
        let alt: String
        let remoteURL: URL?
        let localURL: URL?
    }

    /// Open the lightbox for a Markdown image source. No-ops when the source
    /// resolves to neither a remote nor a local URL, so a broken reference can't
    /// raise an empty overlay.
    func present(source: String, alt: String, libraryURL: URL?) {
        let remote = AssetImageLoader.remoteURL(source: source)
        let local = remote == nil ? AssetImageLoader.localURL(source: source, libraryURL: libraryURL) : nil
        guard remote != nil || local != nil else { return }
        target = Target(alt: alt, remoteURL: remote, localURL: local)
    }

    func dismiss() {
        target = nil
    }
}
