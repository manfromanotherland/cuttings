// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ImageIO

/// Resolves and decodes the images referenced by article Markdown, shared by the
/// inline reader figure (`AssetImageView`) and the full-screen zoom
/// (`ImageLightbox`). Keeping path resolution and ImageIO downsampling in one
/// place means the figure and the lightbox agree on where an asset lives and how
/// it decodes — only the target pixel size differs (a small thumbnail for the
/// inline figure, a larger decode for the zoom).
enum AssetImageLoader {
    /// Wraps an `NSImage` so a decode performed in a detached task can cross the
    /// actor boundary back to the main actor. Safe because the image is fully
    /// built inside that task and never mutated afterward — ownership transfers
    /// to the main actor.
    struct Decoded: @unchecked Sendable {
        let image: NSImage
    }

    /// The on-disk folder that one reading's relative asset links resolve
    /// against: `libraryURL/articles/<prefix>/<id>/`, where `<prefix>` is the
    /// first two characters of the id. This mirrors the library-format fan-out
    /// layout (see `docs/library-format.md`); keeping it in one place means the
    /// reader encodes that layout knowledge exactly once. Returns `nil` when
    /// there is no library or no id.
    static func readingFolderURL(libraryURL: URL?, readingID: String) -> URL? {
        guard let libraryURL, !readingID.isEmpty else { return nil }
        let prefix = String(readingID.prefix(2))
        return libraryURL
            .appendingPathComponent("articles")
            .appendingPathComponent(prefix)
            .appendingPathComponent(readingID)
    }

    /// Resolve a relative asset path to an on-disk URL. Each reading is a
    /// self-contained folder holding `article.md` beside its `assets/`, so the
    /// stored Markdown references assets as `assets/<file>` — resolved directly
    /// under `assetBaseURL` (the reading's folder, from `readingFolderURL`). An
    /// image the extension couldn't capture at save time is still an absolute
    /// `http(s)` URL — not a local asset — so this returns `nil` for it and the
    /// reader shows a placeholder instead of fetching it over the network.
    static func localURL(source: String, assetBaseURL: URL?) -> URL? {
        guard let assetBaseURL else { return nil }
        if let scheme = URL(string: source)?.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            return nil
        }
        // Links are relative to the article file (`assets/<file>`); drop a
        // leading `./` if present, then resolve under the reading's folder.
        var path = source
        if path.hasPrefix("./") {
            path = String(path.dropFirst(2))
        }
        return assetBaseURL.appendingPathComponent(path)
    }

    /// Decode `url` into an image whose largest dimension is at most `maxPixel`
    /// device pixels, using ImageIO so the full-resolution bitmap is never
    /// materialized. Smaller source images are left as-is (no upscaling).
    /// Returns `nil` if the file can't be read or decoded.
    nonisolated static func downsampledImage(at url: URL, maxPixel: CGFloat) -> Decoded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel.rounded())
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return Decoded(image: NSImage(cgImage: cgImage, size: size))
    }
}
