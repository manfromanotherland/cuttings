// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Deterministic Core Image k-means palette extraction.
///
/// Explicit, fixed seed colours avoid a random initial palette. Near-identical
/// output clusters are merged, zero-weight clusters are discarded, and the
/// remainder is normalised and ordered by descending coverage.
enum VisualPaletteExtractor {
    static let clusterCount = 8
    private static let passes: Float = 10
    private static let minimumWeight = 0.000_001
    private static let mergeDistanceSquared = 0.000_4

    static func clusters(from image: CGImage) throws -> [VisualColorCluster] {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VisualAnalysisError.paletteExtractionFailed
        }

        let input = CIImage(cgImage: image, options: [.colorSpace: sRGB])
        // Transparent pixels have no intrinsic visible colour. Composite them
        // over a fixed white background so palette weights remain repeatable
        // and never depend on the window appearance behind the image.
        let background = CIImage(color: CIColor.white).cropped(to: input.extent)
        let opaqueInput = input.composited(over: background)
        let filter = CIFilter.kMeans()
        filter.inputImage = opaqueInput
        filter.extent = opaqueInput.extent
        filter.inputMeans = initialMeans(colorSpace: sRGB)
        filter.count = clusterCount
        filter.passes = passes
        // The perceptual mode emits means encoded in Core Image's internal
        // perceptual space. Keep clustering in the explicitly managed sRGB
        // working space so the returned components are genuinely sRGB values.
        filter.perceptual = false

        guard let output = filter.outputImage else {
            throw VisualAnalysisError.paletteExtractionFailed
        }

        let context = CIContext(options: [
            .workingColorSpace: sRGB,
            .outputColorSpace: sRGB,
            .cacheIntermediates: false
        ])
        var pixels = [Float](repeating: 0, count: clusterCount * 4)
        do {
            try pixels.withUnsafeMutableBytes { buffer in
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
                // CIKMeans uses alpha as a semantic cluster weight rather
                // than opacity. An explicitly unpremultiplied destination
                // preserves the independently encoded sRGB centre and weight.
                destination.alphaMode = .unpremultiplied
                destination.colorSpace = sRGB
                let task = try context.startTask(
                    toRender: output,
                    from: output.extent,
                    to: destination,
                    at: .zero
                )
                try task.waitUntilCompleted()
            }
        } catch {
            throw VisualAnalysisError.paletteExtractionFailed
        }

        let raw: [VisualColorCluster] = stride(
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

        guard !raw.isEmpty else {
            throw VisualAnalysisError.paletteExtractionFailed
        }

        return normalized(merging: raw)
    }

    private static func initialMeans(colorSpace: CGColorSpace) -> CIImage? {
        // Fixed corners of sRGB plus middle grey give every run identical
        // starting conditions while covering the full colour cube.
        let values: [Float] = [
            0, 0, 0, 1,
            1, 1, 1, 1,
            1, 0, 0, 1,
            0, 1, 0, 1,
            0, 0, 1, 1,
            0, 1, 1, 1,
            1, 0, 1, 1,
            0.5, 0.5, 0.5, 1
        ]
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: clusterCount * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: clusterCount, height: 1),
            format: .RGBAf,
            colorSpace: colorSpace
        )
    }

    private static func normalized(
        merging clusters: [VisualColorCluster]
    ) -> [VisualColorCluster] {
        struct Accumulator {
            var redTimesWeight: Double
            var greenTimesWeight: Double
            var blueTimesWeight: Double
            var weight: Double

            var red: Double { redTimesWeight / weight }
            var green: Double { greenTimesWeight / weight }
            var blue: Double { blueTimesWeight / weight }
        }

        var accumulators: [Accumulator] = []
        for cluster in clusters.sorted(by: stableClusterOrder) {
            if let index = accumulators.firstIndex(where: { accumulator in
                let red = accumulator.red - cluster.red
                let green = accumulator.green - cluster.green
                let blue = accumulator.blue - cluster.blue
                return red * red + green * green + blue * blue <= mergeDistanceSquared
            }) {
                accumulators[index].redTimesWeight += cluster.red * cluster.weight
                accumulators[index].greenTimesWeight += cluster.green * cluster.weight
                accumulators[index].blueTimesWeight += cluster.blue * cluster.weight
                accumulators[index].weight += cluster.weight
            } else {
                accumulators.append(Accumulator(
                    redTimesWeight: cluster.red * cluster.weight,
                    greenTimesWeight: cluster.green * cluster.weight,
                    blueTimesWeight: cluster.blue * cluster.weight,
                    weight: cluster.weight
                ))
            }
        }

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

    private static func stableClusterOrder(
        _ lhs: VisualColorCluster,
        _ rhs: VisualColorCluster
    ) -> Bool {
        if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
        if lhs.red != rhs.red { return lhs.red > rhs.red }
        if lhs.green != rhs.green { return lhs.green > rhs.green }
        return lhs.blue > rhs.blue
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}
