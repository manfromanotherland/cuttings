// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

enum MasonryColumnWidthBucket {
    static let quantum: CGFloat = 2

    static func bucket(for width: CGFloat) -> Int {
        Int(floor(width / quantum))
    }

    static func width(for bucket: Int) -> CGFloat {
        CGFloat(bucket) * quantum
    }
}

/// A compact lookup key used by the collection layout after card geometry has
/// been prepared away from the main actor.
struct MasonryCardHeightKey: Hashable, Sendable {
    let readingID: String
    let widthBucket: Int

    init(readingID: String, width: CGFloat) {
        self.readingID = readingID
        widthBucket = Self.bucket(for: width)
    }

    static func bucket(for width: CGFloat) -> Int {
        Int(width.rounded())
    }
}

/// Precomputes deterministic text and media heights for every card density.
/// `NSString.boundingRect` is too expensive to call thousands of times in an
/// `NSCollectionViewLayout.prepare()` transaction, so the board waits for this
/// actor once per page and then layout is reduced to dictionary lookups.
actor MasonryCardHeightLoader {
    static let shared = MasonryCardHeightLoader()

    private static let maximumCacheEntryCount = 50000
    private var cache: [CacheKey: CGFloat] = [:]
    private var cachedWidthBuckets: Set<Int> = []

    func heights(
        for rows: [ReadingRow],
        aspectRatios: [String: CGFloat],
        widths: [CGFloat]
    ) -> [MasonryCardHeightKey: CGFloat] {
        let widthsByBucket = Dictionary(
            widths.map { (MasonryCardHeightKey.bucket(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let requestedWidthBuckets = Set(widthsByBucket.keys)
        if requestedWidthBuckets != cachedWidthBuckets {
            cache.removeAll(keepingCapacity: true)
            cachedWidthBuckets = requestedWidthBuckets
        }

        let fonts = Fonts()
        var result: [MasonryCardHeightKey: CGFloat] = [:]
        result.reserveCapacity(rows.count * widthsByBucket.count)

        for row in rows {
            guard !Task.isCancelled else { return [:] }
            let identity = MasonryCardGeometryIdentity(row: row)
            let ratio = aspectRatios[row.id]
            let ratioBucket = ratio.map { Int(($0 * 100_000).rounded()) }
            for (widthBucket, width) in widthsByBucket {
                guard !Task.isCancelled else { return [:] }
                let cacheKey = CacheKey(
                    identity: identity,
                    widthBucket: widthBucket,
                    ratioBucket: ratioBucket
                )
                let height: CGFloat
                if let cached = cache[cacheKey] {
                    height = cached
                } else {
                    height = Self.height(
                        for: row,
                        width: width,
                        aspectRatio: ratio,
                        fonts: fonts
                    )
                    if cache.count < Self.maximumCacheEntryCount {
                        cache[cacheKey] = height
                    }
                }
                result[MasonryCardHeightKey(readingID: row.id, width: width)] = height
            }
        }
        return result
    }

    private nonisolated static func height(
        for row: ReadingRow,
        width: CGFloat,
        aspectRatio: CGFloat?,
        fonts: Fonts
    ) -> CGFloat {
        let sourceHeight = max(14, ceil(fonts.source.boundingRectForFont.height))
        switch row.kind {
        case .image:
            return mediaHeight(width: width, ratio: aspectRatio, fallbackRatio: 4 / 3)
        case .video:
            return mediaHeight(width: width, ratio: aspectRatio, fallbackRatio: 16 / 9)
        case .quote:
            let text = row.excerpt.flatMap { $0.isEmpty ? nil : $0 } ?? displayTitle(for: row)
            let quoteHeight = textHeight(
                text,
                font: fonts.quote,
                width: width - 44,
                lineLimit: 12,
                lineSpacing: 4
            )
            return ceil(44 + 24 + 36 + quoteHeight + sourceHeight)
        case .article:
            if row.previewAsset != nil {
                let imageHeight = mediaHeight(
                    width: width,
                    ratio: aspectRatio,
                    fallbackRatio: 3 / 2
                )
                let titleHeight = textHeight(
                    displayTitle(for: row),
                    font: fonts.previewTitle,
                    width: width - 30,
                    lineLimit: 3
                )
                return ceil(imageHeight + 30 + titleHeight + 6 + sourceHeight)
            }

            let titleHeight = textHeight(
                displayTitle(for: row),
                font: fonts.articleTitle,
                width: width - 32,
                lineLimit: 5
            )
            let excerpt = row.excerpt.flatMap { $0.isEmpty ? nil : $0 }
            let excerptHeight = excerpt.map {
                textHeight(
                    $0,
                    font: fonts.excerpt,
                    width: width - 32,
                    lineLimit: 6
                )
            } ?? 0
            let spacing = excerpt == nil ? 8 : 16
            return ceil(32 + titleHeight + CGFloat(spacing) + excerptHeight + sourceHeight)
        }
    }

    private nonisolated static func mediaHeight(
        width: CGFloat,
        ratio: CGFloat?,
        fallbackRatio: CGFloat
    ) -> CGFloat {
        let resolvedRatio = ratio.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        } ?? fallbackRatio
        return ceil(width / resolvedRatio)
    }

    private nonisolated static func displayTitle(for row: ReadingRow) -> String {
        row.title.isEmpty ? row.url : row.title
    }

    private nonisolated static func textHeight(
        _ text: String,
        font: NSFont,
        width: CGFloat,
        lineLimit: Int,
        lineSpacing: CGFloat = 0
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        let lineHeight = font.ascender - font.descender + font.leading + lineSpacing
        return min(ceil(bounds.height), ceil(lineHeight * CGFloat(lineLimit)))
    }

    private struct Fonts: @unchecked Sendable {
        let articleTitle = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let excerpt = NSFont.systemFont(ofSize: 12)
        let previewTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let quote: NSFont = {
            let font = NSFont.systemFont(ofSize: 17)
            let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }()

        let source = NSFont.systemFont(ofSize: 10)
    }

    private struct CacheKey: Hashable {
        let identity: MasonryCardGeometryIdentity
        let widthBucket: Int
        let ratioBucket: Int?
    }
}
