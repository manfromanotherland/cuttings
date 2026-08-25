// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CuttingsCardView: View {
    @Environment(AppState.self) private var appState

    let row: ReadingRow
    let playbackPositions: VideoPlaybackPositionStore
    var viewportSize: CGSize = .zero
    var previewMaxPixel: CGFloat = 800
    var autoplayEnabled = true
    var reduceMotion = false
    var scenePhase: ScenePhase = .active
    var onOpen: () -> Void
    var onEditTags: () -> Void

    @State private var isHovered = false

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CuttingsTheme.cardBackground(for: row))
            .clipShape(cardShape)
            .overlay(cardShape.stroke(CuttingsTheme.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) { hoverMenu }
            .contentShape(cardShape)
            .onTapGesture(perform: onOpen)
            .contextMenu {
                CuttingsReadingActions(
                    row: row,
                    onEditTags: onEditTags
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
            fallbackAspectRatio: 4 / 3, maxPixel: previewMaxPixel, contentMode: .fit
        )
    }

    private var videoCard: some View {
        AutoplayVideoCard(
            row: row,
            libraryURL: appState.libraryURL,
            viewportSize: viewportSize,
            playbackPositions: playbackPositions,
            maxPixel: previewMaxPixel,
            autoplayEnabled: autoplayEnabled,
            reduceMotion: reduceMotion,
            scenePhase: scenePhase
        )
    }

    @ViewBuilder
    private var articleCard: some View {
        if row.previewAsset != nil {
            VStack(alignment: .leading, spacing: 0) {
                LocalReadingImage(
                    row: row, libraryURL: appState.libraryURL,
                    fallbackAspectRatio: 3 / 2, maxPixel: previewMaxPixel, contentMode: .fill
                )
                articleText
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.displayTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(articlePrimaryForeground)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                if let excerpt = row.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.callout)
                        .foregroundStyle(articleSecondaryForeground)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                sourceLine(foreground: articleSecondaryForeground)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CuttingsTheme.cardBackground(for: row))
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

            sourceLine(foreground: .secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CuttingsTheme.cardTint(for: row.id))
    }

    private var articleText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.displayTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(articlePrimaryForeground)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            sourceLine(foreground: articleSecondaryForeground)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceLine(foreground: Color) -> some View {
        HStack(spacing: 6) {
            if row.kind == .article, row.faviconAsset != nil {
                LocalReadingFavicon(row: row, libraryURL: appState.libraryURL)
            }

            Text(row.displaySite ?? "Saved locally")
                .lineLimit(1)
        }
        .font(.caption2.weight(.regular))
        .foregroundStyle(foreground)
    }

    private var articlePrimaryForeground: Color {
        CuttingsTheme.articlePalette(for: row)?.foreground.color ?? .primary
    }

    private var articleSecondaryForeground: Color {
        // A themed surface uses the same pure black/white foreground for every
        // text role so captions never lose contrast through opacity. Font size
        // and weight continue to provide the hierarchy.
        CuttingsTheme.articlePalette(for: row)?.foreground.color ?? .secondary
    }

    private var hoverMenu: some View {
        Menu {
            CuttingsReadingActions(
                row: row,
                onEditTags: onEditTags
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
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}
