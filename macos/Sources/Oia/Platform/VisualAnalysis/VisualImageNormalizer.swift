// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// Decodes once, applies EXIF orientation, bounds memory use, and converts the
/// bitmap to a known sRGB representation shared by Vision and colour analysis.
enum VisualImageNormalizer {
    static func normalizedImage(at url: URL, maximumPixelDimension: Int) throws -> CGImage {
        let imageData: Data
        do {
            imageData = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw VisualAnalysisError.unreadableImage(url)
        }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw VisualAnalysisError.unsupportedImage(url)
        }
        if isDeterministicallyInvalid(source) {
            throw VisualAnalysisError.unsupportedImage(url)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelDimension)
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            if isDeterministicallyInvalid(source) {
                throw VisualAnalysisError.unsupportedImage(url)
            }
            // A known decoder can also fail because of transient resource or
            // subsystem pressure. Do not persist that as unsupported.
            throw VisualAnalysisError.imageNormalizationFailed
        }

        return try convertedToSRGB(oriented)
    }

    private static func isDeterministicallyInvalid(_ source: CGImageSource) -> Bool {
        switch CGImageSourceGetStatus(source) {
        case .statusUnexpectedEOF, .statusInvalidData, .statusUnknownType:
            true
        default:
            false
        }
    }

    static func convertedToSRGB(_ image: CGImage) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw VisualAnalysisError.imageNormalizationFailed
        }

        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard let normalized = context.makeImage() else {
            throw VisualAnalysisError.imageNormalizationFailed
        }
        return normalized
    }
}
