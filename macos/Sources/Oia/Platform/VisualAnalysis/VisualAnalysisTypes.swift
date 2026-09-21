// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One label emitted by the system Vision classifier.
///
/// No confidence threshold is applied here. The Rust core can retain the full
/// taxonomy and choose a search-specific precision/recall policy later.
struct VisualLabel: Codable, Equatable, Sendable {
    let identifier: String
    let confidence: Double
}

/// One weighted sRGB colour returned by the visual analyser.
///
/// Components and weight are normalised to `0 ... 1`. Weights across the
/// returned clusters sum to one, within floating-point tolerance.
struct VisualColorCluster: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let weight: Double
}

/// Rebuildable visual facts for one local image asset.
struct VisualAnalysisResult: Codable, Equatable, Sendable {
    let analyzerVersion: String
    let labels: [VisualLabel]
    let colors: [VisualColorCluster]
}

/// The seam used by the app now and by a future FFI adapter.
protocol VisualAnalyzing: Sendable {
    func analyze(imageAt url: URL) async throws -> VisualAnalysisResult
}

enum VisualAnalysisError: Error, LocalizedError, Sendable {
    case unreadableImage(URL)
    case unsupportedImage(URL)
    case imageNormalizationFailed
    case classificationProducedNoResults
    case paletteExtractionFailed

    /// Only deterministic source-byte failures may be persisted as
    /// `supported = false`. I/O, Vision, Core Image, cancellation, and resource
    /// failures remain retryable.
    var isPermanentlyUnsupported: Bool {
        if case .unsupportedImage = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case let .unreadableImage(url):
            "The image at \(url.path) could not be read."
        case let .unsupportedImage(url):
            "The bytes at \(url.path) are not a supported image."
        case .imageNormalizationFailed:
            "The image could not be converted to an oriented sRGB bitmap."
        case .classificationProducedNoResults:
            "Vision completed without image classifications."
        case .paletteExtractionFailed:
            "Core Image could not calculate a colour palette."
        }
    }
}
