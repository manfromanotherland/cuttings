// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Vision

/// On-device visual analysis available on Cuttings' macOS 14 baseline.
struct AppleVisualAnalyzer: VisualAnalyzing, Sendable {
    static let analyzerVersion = "vision-classify-r2+core-image-kmeans-srgb-v2"

    private static let maximumPixelDimension = 2048
    private let executor: VisualAnalysisExecutor

    init(maximumConcurrentAnalyses: Int = 2) {
        executor = VisualAnalysisExecutor(limit: maximumConcurrentAnalyses)
    }

    func analyze(imageAt url: URL) async throws -> VisualAnalysisResult {
        let standardizedURL = url.standardizedFileURL
        return try await executor.run {
            let image = try VisualImageNormalizer.normalizedImage(
                at: standardizedURL,
                maximumPixelDimension: Self.maximumPixelDimension
            )

            let request = VNClassifyImageRequest()
            request.revision = VNClassifyImageRequestRevision2
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            try handler.perform([request])
            guard let observations = request.results else {
                throw VisualAnalysisError.classificationProducedNoResults
            }

            let labels = observations.map { observation in
                VisualLabel(
                    identifier: observation.identifier,
                    confidence: Double(observation.confidence)
                )
            }.sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.identifier < rhs.identifier
            }

            return try VisualAnalysisResult(
                analyzerVersion: Self.analyzerVersion,
                labels: labels,
                colors: VisualPaletteExtractor.clusters(from: image)
            )
        }
    }
}
