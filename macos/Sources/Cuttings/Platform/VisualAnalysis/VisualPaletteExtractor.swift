// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Deterministic Core Image k-means palette extraction.
///
/// Image-derived seed colours avoid both random output and the tendency of
/// fixed colour-cube seeds to collapse pale surfaces into white. Near-identical
/// output clusters are merged, zero-weight clusters are discarded, and the
/// remainder is normalised and ordered by descending coverage.
enum VisualPaletteExtractor {
    private struct Accumulator {
        var redTimesWeight: Double
        var greenTimesWeight: Double
        var blueTimesWeight: Double
        var weight: Double

        var red: Double {
            redTimesWeight / weight
        }

        var green: Double {
            greenTimesWeight / weight
        }

        var blue: Double {
            blueTimesWeight / weight
        }

        init(_ cluster: VisualColorCluster) {
            redTimesWeight = cluster.red * cluster.weight
            greenTimesWeight = cluster.green * cluster.weight
            blueTimesWeight = cluster.blue * cluster.weight
            weight = cluster.weight
        }

        mutating func merge(_ cluster: VisualColorCluster) {
            redTimesWeight += cluster.red * cluster.weight
            greenTimesWeight += cluster.green * cluster.weight
            blueTimesWeight += cluster.blue * cluster.weight
            weight += cluster.weight
        }

        func isNear(_ cluster: VisualColorCluster) -> Bool {
            let redDistance = red - cluster.red
            let greenDistance = green - cluster.green
            let blueDistance = blue - cluster.blue
            return redDistance * redDistance
                + greenDistance * greenDistance
                + blueDistance * blueDistance <= mergeDistanceSquared
        }
    }

    static let clusterCount = 8
    private static let passes: Float = 10
    private static let minimumWeight = 0.000_001
    private static let mergeDistanceSquared = 0.000_4

    static func clusters(from image: CGImage) throws -> [VisualColorCluster] {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VisualAnalysisError.paletteExtractionFailed
        }

        let output = try paletteImage(from: image, colorSpace: sRGB)
        let pixels = try renderedPixels(
            from: output.image,
            clusterCount: output.count,
            colorSpace: sRGB
        )
        let rawClusters = clusters(from: pixels)
        guard !rawClusters.isEmpty else {
            throw VisualAnalysisError.paletteExtractionFailed
        }
        return normalized(merging: rawClusters)
    }

    private static func paletteImage(
        from image: CGImage,
        colorSpace: CGColorSpace
    ) throws -> (image: CIImage, count: Int) {
        let input = CIImage(cgImage: image, options: [.colorSpace: colorSpace])
        // Transparent pixels have no intrinsic visible colour. Composite them
        // over a fixed white background so palette weights remain repeatable
        // and never depend on the window appearance behind the image.
        let background = CIImage(color: CIColor.white).cropped(to: input.extent)
        let opaqueInput = input.composited(over: background)
        let filter = CIFilter.kMeans()
        filter.inputImage = opaqueInput
        filter.extent = opaqueInput.extent
        let seeds = try VisualPaletteSeedGenerator.palette(
            from: image,
            colorSpace: colorSpace,
            maximumCount: clusterCount
        )
        filter.inputMeans = seeds.image
        filter.count = seeds.count
        filter.passes = passes
        // The perceptual mode emits means encoded in Core Image's internal
        // perceptual space. Keep clustering in the explicitly managed sRGB
        // working space so the returned components are genuinely sRGB values.
        filter.perceptual = false

        guard let output = filter.outputImage else {
            throw VisualAnalysisError.paletteExtractionFailed
        }
        return (output, seeds.count)
    }

    private static func renderedPixels(
        from output: CIImage,
        clusterCount: Int,
        colorSpace: CGColorSpace
    ) throws -> [Float] {
        let context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
            .cacheIntermediates: false
        ])
        var pixels = [Float](repeating: 0, count: clusterCount * 4)
        do {
            try pixels.withUnsafeMutableBytes { buffer in
                try render(
                    output,
                    into: buffer,
                    clusterCount: clusterCount,
                    colorSpace: colorSpace,
                    context: context
                )
            }
        } catch {
            throw VisualAnalysisError.paletteExtractionFailed
        }
        return pixels
    }

    private static func render(
        _ output: CIImage,
        into buffer: UnsafeMutableRawBufferPointer,
        clusterCount: Int,
        colorSpace: CGColorSpace,
        context: CIContext
    ) throws {
        guard let baseAddress = buffer.baseAddress else {
            throw VisualAnalysisError.paletteExtractionFailed
        }
        let destination = CIRenderDestination(
            bitmapData: baseAddress,
            width: clusterCount,
            height: 1,
            bytesPerRow: clusterCount * 4 * MemoryLayout<Float>.size,
            format: .RGBAf
        )
        // CIKMeans uses alpha as a semantic cluster weight, not pixel opacity,
        // while its RGB channels already contain the independent cluster
        // centre. Preserve those raw channels: an unpremultiplied destination
        // would divide each centre by its weight and wash pale colours to white.
        destination.alphaMode = .premultiplied
        destination.colorSpace = colorSpace
        let task = try context.startTask(
            toRender: output,
            from: output.extent,
            to: destination,
            at: .zero
        )
        try task.waitUntilCompleted()
    }

    private static func clusters(from pixels: [Float]) -> [VisualColorCluster] {
        stride(
            from: 0,
            to: pixels.count,
            by: 4
        ).compactMap { offset -> VisualColorCluster? in
            let weight = Double(pixels[offset + 3])
            guard weight.isFinite, weight > minimumWeight else { return nil }
            return VisualColorCluster(
                red: clamped(Double(pixels[offset])),
                green: clamped(Double(pixels[offset + 1])),
                blue: clamped(Double(pixels[offset + 2])),
                weight: clamped(weight)
            )
        }
    }

    private static func normalized(
        merging clusters: [VisualColorCluster]
    ) -> [VisualColorCluster] {
        let accumulators = mergedAccumulators(clusters)
        let totalWeight = accumulators.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return [] }

        return accumulators.map { accumulator in
            VisualColorCluster(
                red: clamped(accumulator.red),
                green: clamped(accumulator.green),
                blue: clamped(accumulator.blue),
                weight: accumulator.weight / totalWeight
            )
        }.sorted(by: stableClusterOrder)
    }

    private static func mergedAccumulators(
        _ clusters: [VisualColorCluster]
    ) -> [Accumulator] {
        var accumulators: [Accumulator] = []
        for cluster in clusters.sorted(by: stableClusterOrder) {
            if let index = accumulators.firstIndex(where: { $0.isNear(cluster) }) {
                accumulators[index].merge(cluster)
            } else {
                accumulators.append(Accumulator(cluster))
            }
        }
        return accumulators
    }

    private static func stableClusterOrder(
        _ lhs: VisualColorCluster,
        _ rhs: VisualColorCluster
    ) -> Bool {
        if lhs.weight != rhs.weight {
            return lhs.weight > rhs.weight
        }
        if lhs.red != rhs.red {
            return lhs.red > rhs.red
        }
        if lhs.green != rhs.green {
            return lhs.green > rhs.green
        }
        return lhs.blue > rhs.blue
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}
