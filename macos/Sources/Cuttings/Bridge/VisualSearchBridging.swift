// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One analyzer-versioned visual-analysis job from the disposable core index.
struct VisualAnalysisWorkItem: Equatable, Sendable {
    let readingID: String
    let relativePath: String
    let fileURL: URL
    let contentHash: String
    let analyzerVersion: String
}

/// One current staged visual asset that can be donated to platform search.
struct VisualAssetSnapshot: Equatable, Sendable {
    let readingID: String
    let title: String
    let relativePath: String
    let fileURL: URL
    let contentHash: String
}

struct VisualAnalysisLabelFact: Equatable, Sendable {
    let identifier: String
    let confidence: Double
}

struct VisualAnalysisColorFact: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let weight: Double
}

/// Platform analysis facts to persist in the core's rebuildable cache.
struct VisualAnalysisCompletion: Equatable, Sendable {
    let supported: Bool
    let labels: [VisualAnalysisLabelFact]
    let palette: [VisualAnalysisColorFact]

    static let unsupported = VisualAnalysisCompletion(
        supported: false,
        labels: [],
        palette: []
    )
}

/// The narrow bridge surface needed by background visual indexing.
protocol VisualSearchCore: Sendable {
    func pendingVisualAnalysis(
        analyzerVersion: String, limit: UInt32
    ) async throws -> [VisualAnalysisWorkItem]
    @discardableResult func completeVisualAnalysis(
        task: VisualAnalysisWorkItem, result: VisualAnalysisCompletion
    ) async throws -> Bool
    func currentVisualAssets() async throws -> [VisualAssetSnapshot]
}

// MARK: - FFI boundary mapping

extension VisualAnalysisWorkItem {
    init(_ task: FfiVisualAnalysisTask) {
        readingID = task.readingId
        relativePath = task.relativePath
        fileURL = URL(fileURLWithPath: task.absoluteFilePath)
        contentHash = task.contentHash
        analyzerVersion = task.analyzerVersion
    }

    var ffi: FfiVisualAnalysisTask {
        FfiVisualAnalysisTask(
            readingId: readingID,
            relativePath: relativePath,
            absoluteFilePath: fileURL.path,
            contentHash: contentHash,
            analyzerVersion: analyzerVersion
        )
    }
}

extension VisualAssetSnapshot {
    init(_ asset: FfiVisualAsset) {
        readingID = asset.readingId
        title = asset.title
        relativePath = asset.relativePath
        fileURL = URL(fileURLWithPath: asset.absoluteFilePath)
        contentHash = asset.contentHash
    }
}

extension VisualAnalysisCompletion {
    var ffi: FfiVisualAnalysisResult {
        FfiVisualAnalysisResult(
            supported: supported,
            labels: labels.map {
                FfiVisualLabel(identifier: $0.identifier, confidence: $0.confidence)
            },
            palette: palette.map {
                FfiWeightedColor(
                    red: $0.red,
                    green: $0.green,
                    blue: $0.blue,
                    weight: $0.weight
                )
            }
        )
    }
}
