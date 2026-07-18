// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Fixed-height header above the reader's own scroll: the article title and a
/// metadata row (site, author, reading time, and a read-only tag summary). Driven
/// entirely by the passed-in row, so it lives apart from `ArticleDetailView`'s
/// loading state.
struct ArticleHeaderView: View {
    let row: FfiReadingRow
    /// Reader typography, so the title and metadata rescale with the body copy.
    let theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(theme.titleFont)
                .tracking(theme.titleTracking)
                .accessibilityIdentifier(A11y.Detail.title)
            metadataRow
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let site = row.site, !site.isEmpty {
                metadataLabel(site, systemImage: "globe")
            }
            if let author = row.author, !author.isEmpty {
                metadataLabel(author, systemImage: "person")
            }
            if let readingTime = row.readingTimeLabel {
                metadataLabel(readingTime, systemImage: "clock")
                    .help(row.wordCount.map { "\($0) words" } ?? "")
            }
            if !row.tags.isEmpty {
                Spacer()
                // Plain read-only label pushed to the trailing edge; adding
                // / removing tags happens in the tag sheet (the # toolbar
                // button).
                Text(row.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(theme.metadataFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier(A11y.Detail.tags)
            }
        }
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.tightIcon)
            .font(theme.metadataFont)
            .foregroundStyle(.secondary)
    }
}
