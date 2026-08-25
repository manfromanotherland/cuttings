// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CuttingsReadingOverlay: View {
    @Environment(AppState.self) private var appState

    @Binding var row: ReadingRow
    let rows: [ReadingRow]
    var onClose: () -> Void
    var onMove: (Int) -> Void
    var onSelect: (ReadingRow) -> Void
    var canMovePrevious: Bool
    var canMoveNext: Bool
    var onEditTags: () -> Void

    @State private var showsInspector = false

    var body: some View {
        HSplitView {
            gallery

            if showsInspector {
                CuttingsInspectorView(row: row, onEditTags: onEditTags)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(row.displayTitle)
        .navigationBarBackButtonHidden(true)
        .toolbar { detailToolbar }
        .focusedSceneValue(\.detailNavigationActions, detailNavigationActions)
        .onExitCommand {
            guard !appState.isEditingText else { return }
            onClose()
        }
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            CuttingsGalleryStrip(
                rows: rows,
                selectedID: row.id,
                onSelect: onSelect
            )
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: onClose) {
                Label("Back to Library", systemImage: "chevron.backward")
            }
            .help("Back to library (Escape)")
            .accessibilityIdentifier(A11y.Detail.close)
            .keyboardShortcut(.cancelAction)

            Button { onMove(-1) } label: {
                Label("Previous item", systemImage: "chevron.left")
            }
            .help("Previous item (Left Arrow or K)")
            .accessibilityIdentifier(A11y.Detail.previous)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!canMovePrevious || appState.isEditingText)

            Button { onMove(1) } label: {
                Label("Next item", systemImage: "chevron.right")
            }
            .help("Next item (Right Arrow or J)")
            .accessibilityIdentifier(A11y.Detail.next)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!canMoveNext || appState.isEditingText)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: onEditTags) {
                Label("Edit Tags", systemImage: "tag")
            }
            .help("Edit tags")
            .accessibilityIdentifier(A11y.Toolbar.tags)

            Menu {
                if let url = row.sourceURL {
                    Button {
                        ReadingLink.open(url)
                    } label: {
                        Label("Open Source", systemImage: "safari")
                    }
                }

                Button(role: .destructive) {
                    appState.pendingDelete = row
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More actions")

            Button {
                showsInspector.toggle()
            } label: {
                Label(
                    showsInspector ? "Hide Inspector" : "Show Inspector",
                    systemImage: "sidebar.trailing"
                )
            }
            .help(showsInspector ? "Hide inspector" : "Show inspector")
        }
    }

    private var detailNavigationActions: DetailNavigationActions {
        DetailNavigationActions(
            canMovePrevious: canMovePrevious,
            canMoveNext: canMoveNext,
            showsInspector: showsInspector,
            movePrevious: { onMove(-1) },
            moveNext: { onMove(1) },
            toggleInspector: { showsInspector.toggle() }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch row.kind {
        case .article:
            ArticleDetailView(showsToolbar: false)
                .background(Color(nsColor: .textBackgroundColor))
        case .image:
            mediaDetail(showsPlay: false)
        case .video:
            if row.hasLocalVideoAsset {
                LocalReadingVideo(row: row, libraryURL: appState.libraryURL)
            } else {
                mediaDetail(showsPlay: true)
            }
        case .quote:
            CuttingsQuoteDetailView(row: row)
        }
    }

    private func mediaDetail(showsPlay: Bool) -> some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.10)
            LocalReadingImage(
                row: row, libraryURL: appState.libraryURL,
                fallbackAspectRatio: showsPlay ? 16 / 9 : 4 / 3,
                maxPixel: 3200, contentMode: .fit
            )
            .padding(38)

            if showsPlay {
                videoPlayGlyph
            }

            if showsPlay {
                videoSourceButton
            }
        }
    }

    private var videoPlayGlyph: some View {
        Circle()
            .fill(.black.opacity(0.64))
            .frame(width: 72, height: 72)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: 3)
            }
    }

    @ViewBuilder
    private var videoSourceButton: some View {
        if let url = row.sourceURL {
            Button("Open source page") {
                ReadingLink.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.18))
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}

private struct CuttingsQuoteDetailView: View {
    @Environment(AppState.self) private var appState
    let row: ReadingRow

    @State private var bodyText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("“")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(height: 46)

                Text(attributedQuote)
                    .font(.title)
                    .italic()
                    .lineSpacing(8)
                    .textSelection(.enabled)

                if let site = row.displaySite {
                    Text(site)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 70)
            .padding(.vertical, 90)
        }
        .background(CuttingsTheme.cardTint(for: row.id))
        .task(id: row.id) {
            bodyText = await appState.getBody(id: row.id)
        }
    }

    private var displayText: String {
        let source: String = if let bodyText = bodyText?.trimmingCharacters(in: .whitespacesAndNewlines),
                                !bodyText.isEmpty
        {
            bodyText
        } else if let excerpt = row.excerpt, !excerpt.isEmpty {
            excerpt
        } else {
            row.displayTitle
        }
        return source.replacingOccurrences(
            of: #"(?m)^(?:\s*>\s?)+"#,
            with: "",
            options: [.regularExpression],
            range: source.startIndex ..< source.endIndex
        )
    }

    private var attributedQuote: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: displayText, options: options))
            ?? AttributedString(displayText)
    }
}
