// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CuttingsReadingOverlay: View {
    @Environment(AppState.self) private var appState

    @Binding var row: ReadingRow
    var onClose: () -> Void
    var onMove: (Int) -> Void
    var onEditTags: () -> Void

    @FocusState private var receivesKeys: Bool

    var body: some View {
        GeometryReader { proxy in
            let inspectorWidth = min(380, max(320, proxy.size.width * 0.28))
            HStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(CuttingsTheme.border)
                    .frame(width: 1)

                CuttingsInspectorView(row: $row, onEditTags: onEditTags)
                    .frame(width: inspectorWidth)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CuttingsTheme.border, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) { closeButton }
            .overlay(alignment: .top) { navigationButtons }
        }
        .focusable()
        .focused($receivesKeys)
        .onAppear { receivesKeys = true }
        .onExitCommand(perform: onClose)
        .onKeyPress(.leftArrow) {
            onMove(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            onMove(1)
            return .handled
        }
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
            mediaDetail(showsPlay: true)
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

    private var videoSourceButton: some View {
        Button("Open source page") {
            if let url = URL(string: row.url) {
                ReadingLink.open(url)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.18))
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
        .keyboardShortcut(.cancelAction)
        .padding(14)
    }

    private var navigationButtons: some View {
        HStack(spacing: 4) {
            Button { onMove(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            Button { onMove(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .padding(14)
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
