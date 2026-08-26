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

/// Work still requiring Vision plus exact cache hits applied to reading rows.
struct PendingVisualAnalysis: Equatable, Sendable {
    let tasks: [VisualAnalysisWorkItem]
    let hydratedCount: Int
}

struct VisualSearchReconciliation: Equatable, Sendable {
    let analyzedCount: Int
    let hydratedAnalysisCount: Int
    let spotlightIndexedCount: Int
    let spotlightDeletedCount: Int
    let analysisPublicationToken: UInt64
    private let searchStateMayHaveChanged: Bool

    init(
        analyzedCount: Int,
        hydratedAnalysisCount: Int = 0,
        spotlightIndexedCount: Int,
        spotlightDeletedCount: Int,
        analysisPublicationToken: UInt64 = 0,
        searchStateMayHaveChanged: Bool = false
    ) {
        self.analyzedCount = analyzedCount
        self.hydratedAnalysisCount = hydratedAnalysisCount
        self.spotlightIndexedCount = spotlightIndexedCount
        self.spotlightDeletedCount = spotlightDeletedCount
        self.analysisPublicationToken = analysisPublicationToken
        self.searchStateMayHaveChanged = searchStateMayHaveChanged
    }

    var changedSearchResults: Bool {
        searchStateMayHaveChanged
            || changedCardPresentation
            || spotlightIndexedCount > 0
            || spotlightDeletedCount > 0
    }

    var changedCardPresentation: Bool {
        analyzedCount > 0 || hydratedAnalysisCount > 0
    }

    func shouldReloadReadings(hasActiveSearch: Bool) -> Bool {
        changedCardPresentation || (changedSearchResults && hasActiveSearch)
    }
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
    ) async throws -> PendingVisualAnalysis
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

extension PendingVisualAnalysis {
    init(_ pending: FfiPendingVisualAnalysis) {
        tasks = pending.tasks.map(VisualAnalysisWorkItem.init)
        hydratedCount = Int(pending.hydratedCount)
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
