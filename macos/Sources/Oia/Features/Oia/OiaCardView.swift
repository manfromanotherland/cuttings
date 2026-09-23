// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct OiaCardView: View {
    @Environment(AppState.self) private var appState

    let row: ReadingRow
    let isSelected: Bool
    let playbackPositions: VideoPlaybackPositionStore
    var viewportSize: CGSize = .zero
    var displayScale: CGFloat = 1
    let scrollState: BoardScrollState
    var autoplayEnabled = true
    var reduceMotion = false
    var scenePhase: ScenePhase = .active
    var onSelect: () -> Void
    var onOpen: () -> Void
    var onEditTags: () -> Void

    @State private var isHovered = false
    @State private var isInViewport = false

    var body: some View {
        GeometryReader { proxy in
            interactiveCard(in: proxy.size)
        }
        .modifier(CardViewportVisibilityModifier(
            isEnabled: row.previewAsset != nil
                || row.localVideoAssetReference != nil
                || row.faviconAsset != nil,
            viewportSize: viewportSize,
            isVisible: $isInViewport
        ))
        .onAppear {
            TestHooks.recordStartupEvent("card")
            TestHooks.recordVisibleCard(id: row.id)
        }
    }

    private func interactiveCard(in size: CGSize) -> some View {
        accessibleCard(in: size)
            .contentShape(cardShape)
            .onTapGesture(count: 2, perform: onOpen)
            .onTapGesture(perform: onSelect)
            .contextMenu {
                OiaReadingActions(
                    row: row,
                    onEditTags: onEditTags
                )
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
    }

    private func accessibleCard(in size: CGSize) -> some View {
        cardSurface(in: size)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isSelected ? "Selected" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction { onSelect() }
            .accessibilityAction(named: "Open") { onOpen() }
    }

    private func cardSurface(in size: CGSize) -> some View {
        cardContent(in: size)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(OiaTheme.cardBackground(for: row))
            .clipShape(cardShape)
            .overlay(cardShape.stroke(OiaTheme.border, lineWidth: 1))
            .overlay { selectionRing }
            .overlay(alignment: .topTrailing) { hoverMenu }
    }

    @ViewBuilder
    private func cardContent(in size: CGSize) -> some View {
        switch row.kind {
        case .image:
            imageCard(in: size)
        case .video:
            videoCard(in: size)
        case .quote:
            quoteCard
        case .article:
            articleCard(in: size)
        }
    }

    private func imageCard(in size: CGSize) -> some View {
        LocalReadingImage(
            row: row, libraryURL: appState.libraryURL,
            fallbackAspectRatio: row.standaloneMediaAspectRatio ?? 4 / 3,
            maxPixel: AssetPreviewLoadPlan.displayMaxPixel(
                for: size, displayScale: displayScale
            ),
            contentMode: .fit,
            loadsProgressively: true,
            isVisible: isInViewport,
            scrollState: scrollState
        )
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func videoCard(in size: CGSize) -> some View {
        AutoplayVideoCard(
            row: row,
            libraryURL: appState.libraryURL,
            cardSize: size,
            playbackPositions: playbackPositions,
            maxPixel: AssetPreviewLoadPlan.displayMaxPixel(
                for: size, displayScale: displayScale
            ),
            isInViewport: isInViewport,
            scrollState: scrollState,
            autoplayEnabled: autoplayEnabled,
            reduceMotion: reduceMotion,
            scenePhase: scenePhase
        )
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func articleCard(in size: CGSize) -> some View {
        if row.previewAsset != nil {
            previewArticleCard(in: size)
        } else {
            textArticleCard
        }
    }

    private func previewArticleCard(in size: CGSize) -> some View {
        let aspectRatio = row.articlePreviewAspectRatio ?? ReadingRow.socialPreviewAspectRatio
        let previewHeight = row.articlePreviewHeight(for: size.width)
            ?? size.width / ReadingRow.socialPreviewAspectRatio

        return VStack(alignment: .leading, spacing: 0) {
            LocalReadingImage(
                row: row, libraryURL: appState.libraryURL,
                fallbackAspectRatio: aspectRatio,
                maxPixel: AssetPreviewLoadPlan.displayMaxPixel(
                    for: CGSize(width: size.width, height: previewHeight),
                    displayScale: displayScale
                ),
                contentMode: .fit,
                loadsProgressively: true,
                isVisible: isInViewport,
                scrollState: scrollState
            )
            .frame(width: size.width, height: previewHeight)
            .clipped()

            articleText
                .layoutPriority(1)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private var textArticleCard: some View {
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
        .background(OiaTheme.cardBackground(for: row))
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            quoteMark("quote.opening")

            Text(quoteText)
                .font(Font(OiaCardTextMetrics.quoteFont))
                .foregroundStyle(.primary)
                .lineSpacing(OiaCardTextMetrics.quoteLineSpacing)
                .multilineTextAlignment(.leading)
                .lineLimit(OiaCardTextMetrics.quoteLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, OiaCardTextMetrics.quoteMarkSpacing)

            quoteMark("quote.closing")
                .padding(.top, OiaCardTextMetrics.quoteMarkSpacing)

            sourceLine(foreground: .secondary)
                .frame(minHeight: OiaCardTextMetrics.quoteSourceLineHeight)
                .padding(.top, OiaCardTextMetrics.quoteSourceSpacing)
        }
        .padding(OiaCardTextMetrics.quotePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OiaTheme.cardTint(for: row.id))
    }

    private func quoteMark(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: OiaCardTextMetrics.quoteMarkSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: .infinity,
                minHeight: OiaCardTextMetrics.quoteMarkHeight,
                maxHeight: OiaCardTextMetrics.quoteMarkHeight,
                alignment: .leading
            )
            .accessibilityHidden(true)
    }

    private var articleText: some View {
        VStack(alignment: .leading, spacing: OiaCardTextMetrics.articleFooterSpacing) {
            Text(row.displayTitle)
                .font(Font(OiaCardTextMetrics.articleTitleFont))
                .foregroundStyle(articlePrimaryForeground)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            sourceLine(foreground: articleSecondaryForeground)
                .frame(minHeight: OiaCardTextMetrics.articleFooterSourceLineHeight)
        }
        .padding(OiaCardTextMetrics.articleFooterPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension OiaCardView {
    private func sourceLine(foreground: Color) -> some View {
        HStack(spacing: 6) {
            if row.kind == .article, row.faviconAsset != nil {
                LocalReadingFavicon(
                    row: row,
                    libraryURL: appState.libraryURL,
                    isVisible: isInViewport
                )
            }

            Text(row.displaySite ?? "Saved locally")
                .lineLimit(1)
        }
        .font(Font(OiaCardTextMetrics.sourceFont))
        .foregroundStyle(foreground)
    }

    private var articlePrimaryForeground: Color {
        OiaTheme.articlePalette(for: row)?.foreground.color ?? .primary
    }

    private var articleSecondaryForeground: Color {
        // A themed surface uses the same pure black/white foreground for every
        // text role so captions never lose contrast through opacity. Font size
        // and weight continue to provide the hierarchy.
        OiaTheme.articlePalette(for: row)?.foreground.color ?? .secondary
    }

    private var hoverMenu: some View {
        Menu {
            OiaReadingActions(
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

    @ViewBuilder
    private var selectionRing: some View {
        if isSelected {
            cardShape
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .allowsHitTesting(false)
        }
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
