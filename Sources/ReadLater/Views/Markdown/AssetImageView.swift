// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO
import SwiftUI

/// Renders a single Markdown image natively, with an optional caption drawn from
/// the image's alt text (a "figure"). Local library assets
/// (`../assets/<id>/<file>`) load from disk under `libraryURL/assets/`;
/// remote `http(s)` images use `AsyncImage`. Replaces the `readlater://`
/// custom-scheme handler the WebView relied on.
struct AssetImageView: View {
    let source: String
    let alt: String
    let libraryURL: URL?
    let theme: MarkdownTheme
    var highlights: [String] = []
    var onHighlight: (String) -> Void = { _ in }

    @State private var localImage: NSImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: theme.captionGap) {
            picture
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: theme.imageCornerRadius))
                .accessibilityLabel(alt)
            if !alt.isEmpty {
                // A selectable text view (rather than SwiftUI `Text`) so the
                // caption supports the same highlight tint and Highlight/Look Up
                // menu as body text.
                SelectableTextView(attributed: captionAttributed,
                                   highlights: highlights, onHighlight: onHighlight)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The alt-text caption as an `NSAttributedString` (centered, secondary,
    /// caption-sized) so it can back a `SelectableTextView`.
    private var captionAttributed: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let font = AppKitInline.makeFont(size: theme.captionSize, weight: .regular,
                                         design: theme.design, bold: false, italic: false)
        return NSAttributedString(string: alt, attributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
    }

    @ViewBuilder
    private var picture: some View {
        if let url = remoteURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    placeholder
                default:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        } else if let localImage {
            Image(nsImage: localImage)
                .resizable()
                .scaledToFit()
        } else if failed {
            placeholder
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80)
                .task(id: source) { await loadLocal() }
        }
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
            Text(alt.isEmpty ? "Image unavailable" : alt)
        }
        .foregroundStyle(.secondary)
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: theme.imageCornerRadius))
    }

    // ── Resolution ──────────────────────────────────────────────────────────

    private var remoteURL: URL? {
        guard let scheme = URL(string: source)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return URL(string: source)
    }

    /// Resolve a relative library asset path to an on-disk URL. The stored
    /// Markdown references assets as `../assets/<id>/<file>`; strip the known
    /// prefixes and resolve under `libraryURL/assets/` (the path the old
    /// `AssetSchemeHandler` reconstructed).
    private var localURL: URL? {
        guard let libraryURL else { return nil }
        var path = source
        for prefix in ["../assets/", "./assets/", "assets/"] {
            if path.hasPrefix(prefix) {
                path = String(path.dropFirst(prefix.count))
                break
            }
        }
        return libraryURL
            .appendingPathComponent("assets")
            .appendingPathComponent(path)
    }

    private func loadLocal() async {
        guard let url = localURL else { failed = true; return }
        // The reader never lays an image out wider than `contentMaxWidth`, so a
        // thumbnail that many device pixels across is all the display needs.
        // Loading at native resolution instead would hold far more memory than
        // the on-screen size warrants, and a long article stacks several images.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maxPixel = theme.contentMaxWidth * scale
        // Decode the downsampled image off the main actor. ImageIO reads only
        // what it needs from disk and never materializes the full-resolution
        // bitmap (`NSImage` is not Sendable, hence the wrapper).
        let decoded = await Task.detached(priority: .userInitiated) {
            AssetImageView.downsampledImage(at: url, maxPixel: maxPixel)
        }.value
        if let decoded {
            localImage = decoded.image
        } else {
            failed = true
        }
    }

    /// Wraps an `NSImage` so it can cross the actor boundary out of the detached
    /// decode task. Safe because the image is fully built inside that task and
    /// never mutated afterward — ownership transfers to the main actor.
    private struct DecodedImage: @unchecked Sendable {
        let image: NSImage
    }

    /// Decode `url` into an image whose largest dimension is at most `maxPixel`
    /// device pixels, using ImageIO so the full-resolution bitmap is never
    /// materialized. Smaller source images are left as-is (no upscaling).
    /// Returns `nil` if the file can't be read or decoded.
    private static nonisolated func downsampledImage(at url: URL, maxPixel: CGFloat) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel.rounded()),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return DecodedImage(image: NSImage(cgImage: cgImage, size: size))
    }
}
