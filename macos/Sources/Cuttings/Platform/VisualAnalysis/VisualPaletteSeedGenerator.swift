// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreImage
import Foundation

struct VisualPaletteSeedPalette {
    let image: CIImage
    let count: Int
}

/// Builds deterministic, image-derived starting means for Core Image k-means.
enum VisualPaletteSeedGenerator {
    private struct Bin {
        var redTotal = 0
        var greenTotal = 0
        var blueTotal = 0
        var population = 0

        mutating func add(red: UInt8, green: UInt8, blue: UInt8) {
            redTotal += Int(red)
            greenTotal += Int(green)
            blueTotal += Int(blue)
            population += 1
        }

        var candidate: Candidate {
            let divisor = Double(population * 255)
            return Candidate(
                red: Double(redTotal) / divisor,
                green: Double(greenTotal) / divisor,
                blue: Double(blueTotal) / divisor,
                population: population
            )
        }
    }

    private struct Candidate {
        let red: Double
        let green: Double
        let blue: Double
        let population: Int

        func distanceSquared(to other: Candidate) -> Double {
            let redDistance = red - other.red
            let greenDistance = green - other.green
            let blueDistance = blue - other.blue
            return redDistance * redDistance
                + greenDistance * greenDistance
                + blueDistance * blueDistance
        }
    }

    private static let sampleDimension = 64
    private static let quantizationShift: UInt8 = 3

    static func palette(
        from image: CGImage,
        colorSpace: CGColorSpace,
        maximumCount: Int
    ) throws -> VisualPaletteSeedPalette {
        var remaining = candidates(from: image, colorSpace: colorSpace)
        guard !remaining.isEmpty else {
            throw VisualAnalysisError.paletteExtractionFailed
        }
        remaining.sort(by: stableOrder)
        let selected = select(from: &remaining, maximumCount: maximumCount)
        return VisualPaletteSeedPalette(
            image: meansImage(from: selected, colorSpace: colorSpace),
            count: selected.count
        )
    }

    private static func select(
        from remaining: inout [Candidate],
        maximumCount: Int
    ) -> [Candidate] {
        var selected = [remaining.removeFirst()]
        while selected.count < maximumCount, !remaining.isEmpty {
            let bestIndex = remaining.indices.max { lhs, rhs in
                selectionScore(remaining[lhs], selected: selected)
                    < selectionScore(remaining[rhs], selected: selected)
            } ?? remaining.startIndex
            selected.append(remaining.remove(at: bestIndex))
        }
        return selected
    }

    private static func selectionScore(
        _ candidate: Candidate,
        selected: [Candidate]
    ) -> Double {
        let nearestDistance = selected.reduce(Double.greatestFiniteMagnitude) {
            min($0, candidate.distanceSquared(to: $1))
        }
        return Double(candidate.population) * nearestDistance
    }

    private static func meansImage(
        from selected: [Candidate],
        colorSpace: CGColorSpace
    ) -> CIImage {
        let values: [Float] = selected.flatMap { candidate in
            [Float(candidate.red), Float(candidate.green), Float(candidate.blue), 1]
        }
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: selected.count * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: selected.count, height: 1),
            format: .RGBAf,
            colorSpace: colorSpace
        )
    }

    private static func candidates(
        from image: CGImage,
        colorSpace: CGColorSpace
    ) -> [Candidate] {
        let width = min(sampleDimension, max(1, image.width))
        let height = min(sampleDimension, max(1, image.height))
        guard let pixels = sampledPixels(
            from: image,
            width: width,
            height: height,
            colorSpace: colorSpace
        ) else { return [] }

        var bins: [Int: Bin] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            addPixel(at: offset, from: pixels, to: &bins)
        }
        return bins.values.map(\.candidate)
    }

    private static func sampledPixels(
        from image: CGImage,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            draw(image, into: buffer, width: width, height: height, colorSpace: colorSpace)
        }
        return rendered ? pixels : nil
    }

    private static func draw(
        _ image: CGImage,
        into buffer: UnsafeMutableRawBufferPointer,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> Bool {
        guard let baseAddress = buffer.baseAddress,
              let context = CGContext(
                  data: baseAddress,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                      | CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return false }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .medium
        context.draw(image, in: bounds)
        return true
    }

    private static func addPixel(
        at offset: Int,
        from pixels: [UInt8],
        to bins: inout [Int: Bin]
    ) {
        let red = pixels[offset]
        let green = pixels[offset + 1]
        let blue = pixels[offset + 2]
        let key = Int(red >> quantizationShift) << 10
            | Int(green >> quantizationShift) << 5
            | Int(blue >> quantizationShift)
        bins[key, default: Bin()].add(red: red, green: green, blue: blue)
    }

    private static func stableOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.population != rhs.population {
            return lhs.population > rhs.population
        }
        if lhs.red != rhs.red {
            return lhs.red > rhs.red
        }
        if lhs.green != rhs.green {
            return lhs.green > rhs.green
        }
        return lhs.blue > rhs.blue
    }
}
