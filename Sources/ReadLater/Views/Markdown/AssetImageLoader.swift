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

    /// The remote URL for an `http(s)` source, or `nil` for a local asset.
    static func remoteURL(source: String) -> URL? {
        guard let scheme = URL(string: source)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return URL(string: source)
    }

    /// Resolve a relative library asset path to an on-disk URL. The stored
    /// Markdown references assets as `../assets/<id>/<file>`; strip the known
    /// prefixes and resolve under `libraryURL/assets/`.
    static func localURL(source: String, libraryURL: URL?) -> URL? {
        guard let libraryURL else { return nil }
        var path = source
        for prefix in ["../assets/", "./assets/", "assets/"] where path.hasPrefix(prefix) {
            path = String(path.dropFirst(prefix.count))
            break
        }
        return libraryURL
            .appendingPathComponent("assets")
            .appendingPathComponent(path)
    }

    /// Decode `url` into an image whose largest dimension is at most `maxPixel`
    /// device pixels, using ImageIO so the full-resolution bitmap is never
    /// materialized. Smaller source images are left as-is (no upscaling).
    /// Returns `nil` if the file can't be read or decoded.
    static nonisolated func downsampledImage(at url: URL, maxPixel: CGFloat) -> Decoded? {
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
