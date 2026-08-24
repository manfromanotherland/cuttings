// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CuttingsCardView: View {
    @Environment(AppState.self) private var appState

    let row: ReadingRow
    var onOpen: () -> Void
    var onEditTags: () -> Void
    var onOptimisticChange: (ReadingRow) -> Void = { _ in }

    @State private var isHovered = false

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity)
            .background(CuttingsTheme.card)
            .clipShape(cardShape)
            .overlay(cardShape.stroke(CuttingsTheme.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) { hoverMenu }
            .contentShape(cardShape)
            .onTapGesture(perform: onOpen)
            .contextMenu {
                CuttingsReadingActions(
                    row: row,
                    onEditTags: onEditTags,
                    onOptimisticChange: onOptimisticChange
                )
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch row.kind {
        case .image:
            imageCard
        case .video:
            videoCard
        case .quote:
            quoteCard
        case .article:
            articleCard
        }
    }

    private var imageCard: some View {
        LocalReadingImage(
            row: row, libraryURL: appState.libraryURL,
            fallbackAspectRatio: 4 / 3, contentMode: .fit
        )
    }

    private var videoCard: some View {
        LocalReadingImage(
            row: row, libraryURL: appState.libraryURL,
            fallbackAspectRatio: 16 / 9, contentMode: .fill
        )
        .overlay {
            Circle()
                .fill(.black.opacity(0.56))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var articleCard: some View {
        if row.previewAsset != nil {
            VStack(alignment: .leading, spacing: 0) {
                LocalReadingImage(
                    row: row, libraryURL: appState.libraryURL,
                    fallbackAspectRatio: 3 / 2, contentMode: .fill
                )
                articleText
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text(row.displayTitle)
                    .font(.title2.weight(.medium))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                if let excerpt = row.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                sourceLine(onDark: false)
            }
            .padding(20)
            .background(CuttingsTheme.cardTint(for: row.id))
        }
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("“")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(height: 24)

            Text(quoteText)
                .font(.title2)
                .italic()
                .lineSpacing(4)
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)

            sourceLine(onDark: false)
        }
        .padding(22)
        .background(CuttingsTheme.cardTint(for: row.id))
    }

    private var articleText: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(row.displayTitle)
                .font(.headline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            sourceLine(onDark: false)
        }
        .padding(15)
    }

    private func sourceLine(onDark: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: row.kind.symbol)
                .font(.system(size: 9, weight: .medium))
            Text(row.displaySite ?? "Saved locally")
                .lineLimit(1)
            if row.favorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(onDark ? Color.white.opacity(0.9) : Color.red.opacity(0.7))
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(onDark ? Color.white.opacity(0.82) : Color.secondary)
    }

    private var hoverMenu: some View {
        Menu {
            CuttingsReadingActions(
                row: row,
                onEditTags: onEditTags,
                onOptimisticChange: onOptimisticChange
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 26)
                .background(.regularMaterial, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(10)
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered)
        .accessibilityLabel("More actions")
    }

    private var quoteText: String {
        if let excerpt = row.excerpt, !excerpt.isEmpty {
            return excerpt
        }
        return row.displayTitle
    }

    private var accessibilityLabel: String {
        [row.kind.singularLabel, row.displayTitle, row.displaySite]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}
