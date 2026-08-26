// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

extension ReadingRow {
    static let socialPreviewAspectRatio: CGFloat = 1200 / 630

    /// The display ratio used by both LazyLayoutKit and the standalone media view.
    /// Keeping one value authoritative prevents decoded media from changing an
    /// already placed card's frame while the user scrolls.
    var standaloneMediaAspectRatio: CGFloat? {
        switch kind {
        case .image:
            validMediaAspectRatio ?? 4 / 3
        case .video:
            validMediaAspectRatio ?? 16 / 9
        case .article, .quote:
            nil
        }
    }

    var articlePreviewAspectRatio: CGFloat? {
        guard kind == .article, previewAsset != nil else { return nil }
        return validMediaAspectRatio ?? Self.socialPreviewAspectRatio
    }

    func articlePreviewHeight(for width: CGFloat) -> CGFloat? {
        height(for: width, aspectRatio: articlePreviewAspectRatio)
    }

    func standaloneMediaHeight(for width: CGFloat) -> CGFloat? {
        height(for: width, aspectRatio: standaloneMediaAspectRatio)
    }

    private func height(for width: CGFloat, aspectRatio: CGFloat?) -> CGFloat? {
        guard width.isFinite, width > 0,
              let aspectRatio
        else {
            return nil
        }
        return width / aspectRatio
    }

    private var validMediaAspectRatio: CGFloat? {
        guard let mediaAspectRatio,
              mediaAspectRatio.isFinite,
              mediaAspectRatio > 0
        else {
            return nil
        }
        return CGFloat(mediaAspectRatio)
    }
}
