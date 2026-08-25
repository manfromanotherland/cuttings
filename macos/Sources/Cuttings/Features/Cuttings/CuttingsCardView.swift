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
            .background(CuttingsTheme.card)
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CuttingsTheme.cardTint(for: row.id))
    }

    private var articleText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.displayTitle)
                .font(.headline.weight(.semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            sourceLine(onDark: false)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceLine(onDark: Bool) -> some View {
        Text(row.displaySite ?? "Saved locally")
            .lineLimit(1)
            .font(.caption2.weight(.regular))
            .foregroundStyle(onDark ? Color.white.opacity(0.82) : Color.secondary)
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
