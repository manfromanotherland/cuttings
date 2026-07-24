// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Fixed-height header above the reader's own scroll: the article title and a
/// metadata row (reading time on the left, a read-only tag summary on the right).
/// Driven entirely by the passed-in row, so it lives apart from
/// `ArticleDetailView`'s loading state.
struct ArticleHeaderView: View {
    let row: ReadingRow
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
            if let readingTime = row.readingTimeLabel {
                metadataLabel(readingTime, systemImage: "clock")
                    .help(row.wordCount.map { "\($0) words" } ?? "")
            }
            if !row.tags.isEmpty {
                // Plain read-only label; adding / removing tags happens in the
                // tag sheet (the # toolbar button). With site and author gone,
                // the tags sit alongside the reading time and may wrap onto a
                // second line.
                Text(row.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(theme.metadataFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, 12)
                    .accessibilityIdentifier(A11y.Detail.tags)
            }
            Spacer(minLength: 0)
        }
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.tightIcon)
            .font(theme.metadataFont)
            .foregroundStyle(.secondary)
    }
}
