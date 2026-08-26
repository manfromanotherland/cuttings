// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Resolves a reading to an existing local file that system Quick Look can
/// preview. It never hands Quick Look a remote origin or media URL.
enum ReadingQuickLookURLResolver {
    static func previewURL(for row: ReadingRow, libraryURL: URL?) -> URL? {
        guard let readingFolder = AssetImageLoader.readingFolderURL(
            libraryURL: libraryURL,
            readingID: row.id
        ) else { return nil }

        let articleURL = readingFolder.appending(path: "article.md")
        let candidates = mediaCandidates(for: row, readingFolder: readingFolder) + [articleURL]
        return candidates.first(where: isReadableRegularFile)
    }

    private static func mediaCandidates(for row: ReadingRow, readingFolder: URL) -> [URL] {
        switch row.kind {
        case .article, .quote:
            []
        case .image:
            localURL(for: row.previewAsset, readingFolder: readingFolder).map { [$0] } ?? []
        case .video:
            [
                localURL(for: row.localVideoAssetReference, readingFolder: readingFolder),
                localURL(for: row.previewAsset, readingFolder: readingFolder)
            ]
            .compactMap(\.self)
        }
    }

    private static func localURL(for source: String?, readingFolder: URL) -> URL? {
        guard let source else { return nil }
        return AssetImageLoader.localURL(source: source, assetBaseURL: readingFolder)
    }

    private static func isReadableRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
        else { return false }
        return values.isRegularFile == true && values.isReadable == true
    }
}
