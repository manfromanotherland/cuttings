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

    /// Resolve a local asset reference to an on-disk URL under the reading's
    /// folder (`assetBaseURL`, from `readingFolderURL`).
    ///
    /// Only the exact shape core emits is accepted — `assets/<filename>`, one
    /// file inside the reading's own `assets/` folder. Because the library is
    /// synced and externally writable, a crafted link must not be able to read
    /// arbitrary files: absolute paths, `..` traversal, nested or extra path
    /// segments, and any non-`assets/` reference all return `nil`. An image the
    /// extension couldn't capture is still an `http(s)` URL — also not a local
    /// asset — so it returns `nil` too and the reader shows a placeholder rather
    /// than fetching over the network.
    static func localURL(source: String, assetBaseURL: URL?) -> URL? {
        guard let assetBaseURL else { return nil }
        let prefix = "assets/"
        guard source.hasPrefix(prefix) else { return nil }
        let filename = String(source.dropFirst(prefix.count))
        guard isSafeAssetFilename(filename) else { return nil }
        return assetBaseURL
            .appendingPathComponent("assets")
            .appendingPathComponent(filename)
    }

    /// A safe asset filename is a single path component: non-empty, no `/`
    /// (rules out absolute and nested paths), and not `.`/`..` (rules out
    /// traversal). Core writes `<sha256>.<ext>`, so this never rejects a real
    /// asset while refusing anything that could escape the `assets/` folder.
    private static func isSafeAssetFilename(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
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
