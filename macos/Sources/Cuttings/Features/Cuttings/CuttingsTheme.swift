// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

enum CuttingsTheme {
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)

    static func cardTint(for _: String) -> Color {
        card
    }
}

extension ReadingKind {
    var label: String {
        switch self {
        case .article: "Articles"
        case .image: "Images"
        case .quote: "Quotes"
        case .video: "Videos"
        }
    }

    var singularLabel: String {
        switch self {
        case .article: "Article"
        case .image: "Image"
        case .quote: "Quote"
        case .video: "Video"
        }
    }

    var symbol: String {
        switch self {
        case .article: "doc.text"
        case .image: "photo"
        case .quote: "quote.opening"
        case .video: "play.rectangle"
        }
    }
}

extension ReadingRow {
    var displayTitle: String {
        title.isEmpty ? url : title
    }

    /// Only web origins can be opened outside the app. Source-less paste/drop
    /// saves use a private `cuttings://local/...` identity so they remain
    /// content-addressed without leaking a machine-specific file path.
    var sourceURL: URL? {
        guard let url = URL(string: url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    var displaySite: String? {
        if let site, !site.isEmpty {
            return site
        }
        return sourceURL?.host?.replacingOccurrences(of: "www.", with: "")
    }
}
