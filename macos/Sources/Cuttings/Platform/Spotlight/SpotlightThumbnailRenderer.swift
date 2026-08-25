// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SpotlightThumbnailRenderer {
    static func writeThumbnail(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumPixelDimension: Int
    ) throws {
        let image = try VisualImageNormalizer.normalizedImage(
            at: sourceURL,
            maximumPixelDimension: maximumPixelDimension
        )
        let data = try pngData(from: image)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
    }

    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SpotlightVisualIndexError.thumbnailEncodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SpotlightVisualIndexError.thumbnailEncodingFailed
        }
        return data as Data
    }
}
